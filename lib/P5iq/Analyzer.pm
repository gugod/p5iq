package P5iq::Analyzer;
use strict;
use warnings;
use List::MoreUtils qw(uniq);
use Data::Dumper;
use Storable 'dclone';

sub analyze_for_index {
    my ($ppi_doc) = @_;

    $ppi_doc->index_locations;
    $ppi_doc->index_line_to_sub;

    return {
        p5_token => [
            extract_token($ppi_doc),
        ],
        p5_node => [
            extract_subscript($ppi_doc),
        ],
        p5_sub => [
            extract_subroutine($ppi_doc),
            extract_function_calls($ppi_doc),
            extract_method_calls($ppi_doc),
        ],
        p5_package => [
            extract_package($ppi_doc),
        ],
        p5_statement => [
            extract_statements($ppi_doc)
        ],
        p5_dependency => [
            extract_package_dependency($ppi_doc),
        ],
    }
}

sub TypeLineColumn {
    my ($loc) = @_;
    return {
        tag  => join(",", $loc->[0], $loc->[1]),
        line => $loc->[0],
        column => $loc->[1],
    }
}

sub TypeRangeLineColumn {
    my ($begin_ppi_node, $end_ppi_node) = @_;
    $end_ppi_node //= $begin_ppi_node;

    my $begin_loc = [@{ $begin_ppi_node->location }];
    my $end_loc   = [@{ $end_ppi_node->location }];
    my $d = {
        begin => TypeLineColumn($begin_loc),
        end   => TypeLineColumn($end_loc),
        tag   => join(",", $begin_loc->[0], $begin_loc->[1], $end_loc->[0], $end_loc->[1]),
    };
    return $d;
}

sub extract_package_dependency {
    my ($ppi_doc) = @_;

    my $things = $ppi_doc->find(
        sub {
            my $el = pop;
            return $el->isa('PPI::Statement::Package') || $el->isa('PPI::Statement::Include');
        }
    ) or return ();

    my %deps;
    my $current_package = "main";
    for (@$things) {
        if ($_->isa('PPI::Statement::Package')) {
            $current_package = $_->namespace;
        } else {
            push @{$deps{$current_package}}, $_;
        }
    }

    my @doc;
    for my $p (keys %deps) {
        my @deps = ();
        for (@{ $deps{$p} }) {
            my $d = (grep { $_->isa("PPI::Token::Word") } $_->tokens)[1];
            push @deps, $d->content if $d;
        }
        @deps = uniq(@deps);
        push @doc, {
            class         => "P5iq::PackageDependency",
            content       => \@deps,
            tags          => [
                "package:dependency",
                "package:name=" . $p,
            ]
        };
    }

    return @doc;
}

sub extract_statements {
    my ($ppi_doc) = @_;
    my @doc;
    my $statements = $ppi_doc->find(sub { $_[1]->isa('PPI::Statement') });
    for my $s (@$statements) {
        push @doc, {
            class    => $s->class,
            location => TypeRangeLineColumn($s, $s->last_token),
            tags => [
                "statement"
            ]
        };
    }
    return @doc;
}

sub extract_package {
    my ($ppi_doc) = @_;
    my @doc;
    my $sub_nodes = $ppi_doc->find(sub { $_[1]->isa('PPI::Statement::Package') });
    return () unless $sub_nodes;
    for my $el (@$sub_nodes) {
        push @doc, {
            location      => TypeRangeLineColumn($el),
            class         => 'P5iq::Package',
            content       => $el->namespace,
            tags          => [
                "package:def",
                "package:name=" . $el->namespace,
            ]
        }
    }
    return @doc;
}

sub extract_subroutine {
    my ($ppi_doc) = @_;
    my @doc;
    my $sub_nodes = $ppi_doc->find(sub { $_[1]->isa('PPI::Statement::Sub') });
    return () unless $sub_nodes;
    for my $el (@$sub_nodes) {
        my $n = $el->name;
        push @doc, {
            location      => TypeRangeLineColumn($el, $el->last_token),
            class         => 'P5iq::Subroutine',
            content       => $n // "",
            tags          => [
                "subroutine:def",
                (defined($n) ? "subroutine:name=$n" : "subroutine:unnamed")
            ]
        }
    }
    return @doc;
}

sub extract_method_calls {
    my ($ppi_doc) = @_;

    my @doc;
    for my $s (@{ $ppi_doc->find('PPI::Token::Operator') ||[]}) {
        next unless $s->content eq '->';

        my $method = $s->snext_sibling;
        next unless $method->isa('PPI::Token');

        my @invocant;
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            last if !$p->isa('PPI::Token') || $p->isa('PPI::Token::Operator') && $p->content ne '->';
            last if @invocant && $p->isa('PPI::Token::Word') && !$invocant[0]->isa('PPI::Token::Operator');
            unshift(@invocant, $p);
        }

        my $invocant = @invocant ? join("", @invocant) : "???";

        my @arglist_tokens;
        my $args = $method->snext_sibling;
        if ($args && $args->isa('PPI::Structure::List')) {
            @arglist_tokens = map { "$_" } grep { $_->significant && /\p{Letter}/ } $args->tokens;
        }

        push @doc, {
            content       => [ (map {"$_"} @invocant), @arglist_tokens ],
            class         => 'P5iq::MethodCall',
            location      => TypeRangeLineColumn($method, ($args ? $args->last_token : undef)),
            tags          => [
                "method:call",
                "method:name=$method",
                "method:invocant=$invocant",
                ( substr($method,0,1) eq '$' ? "method:dynamic-name" : () ),
                ( $invocant =~ /\A\w+ (:: \w+)* (::)?\z/x ? "method:class" : () ),
            ],
        };
    }
    return @doc;
}

sub extract_function_calls {
    my ($ppi_doc) = @_;
    my @doc;

    # Look for all "word followed by a list within parenthesis"
    # foo(); foo(1,2,3); foo( bar(1,2,3), 4)
    for my $s (@{ $ppi_doc->find('PPI::Token::Word') ||[]}) {
        next unless ref($s->parent) eq 'PPI::Statement';

        my $prev = $s->sprevious_sibling;
        next if ($prev && ref($prev) eq 'PPI::Token::Operator' && $prev->content eq "->");

        my $args = $s->snext_sibling;
        next unless ref($args) eq 'PPI::Structure::List';

        my @arglist_tokens = map { "$_" } grep { $_->significant && /\p{Letter}/ } $args->tokens;

        my (@ns) = split(/::/, "$s");
        my $name = pop(@ns);
        my $namespace = join("::", @ns);
        push @doc, {
            content       => [ (@ns ? "$s" :""), "$name", @arglist_tokens ],
            class         => 'P5iq::FunctionCall',
            location      => TypeRangeLineColumn($s, $args->last_token),
            tags          => [
                "function:call",
                "function:namespace=$namespace",
                "function:name=$name"
            ],
        };
    }

    # TODO: Look for all "word followed by a list not within parenthesis"
    # foo; foo 1,2; foo bar(1,2,3), 4;

    return @doc;
}

sub extract_subscript {
    my ($ppi_doc) = @_;
    my @doc;
    for my $s (@{ $ppi_doc->find('PPI::Structure::Subscript') ||[] }) {
        my @container;
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            unshift @container, $p;
            last if $p->isa("PPI::Token::Symbol");
        }
        my $container_type = ( substr($s,0,1) eq "{" ? "hash": "array" );
        my @subscript_tokens = grep { $_->significant && /\p{Letter}/ } $s->tokens;
        my $doc = {
            location => TypeRangeLineColumn($s, $s->last_token),
            content       => [map {"$_"} @subscript_tokens],
            class         => 'PPI::Structure::Subscript',
            tags          => [
                "subscript:symbol=$container[0]",
                "subscript:container=" . join("", map { $_->content } @container ),
                "subscript:container-type=${container_type}",
            ],
        };
        push @doc, $doc;
    }
    return @doc;
}

sub extract_token {
    my ($ppi_doc) = @_;
    my @doc;
    for my $x ( $ppi_doc->tokens ) {
        next unless $x->significant;
        my $doc = {
            content  => $x->content,
            class    => $x->class,
            tags     => [],
            scope    => [],
            location => TypeRangeLineColumn($x),
        };
        if (ref($x) eq 'PPI::Token::Symbol') {
            push @{$doc->{tags}}, (
                'symbol:actual='    . $x->symbol,
                'symbol:canonical=' . $x->canonical
            );

            fleshen_scope_locations($doc, $x->parent);

            my ($next_op, $prev_op);
            if ( ref(my $x_parent = $x->parent) eq 'PPI::Statement::Variable' ) {
                push @{$doc->{tags}}, 'in:statement:variable';
                $next_op = $_ if ref($_ = $x->snext_sibling) eq 'PPI::Token::Operator';
                $prev_op = $_ if ref($_ = $x->sprevious_sibling) eq 'PPI::Token::Operator';
            }
            # Look for var definition like: my ($a, $b) = @_
            elsif ( ref($x->parent) eq 'PPI::Statement::Expression'
                && ref($x->parent->parent) eq 'PPI::Structure::List'
                && ref($x->parent->parent->parent) eq 'PPI::Statement::Variable') {
                push @{$doc->{tags}}, 'in:statement:variable';
                $next_op = $_ if ref($_ = $x->snext_sibling) eq 'PPI::Token::Operator';
                $prev_op = $_ if ref($_ = $x->sprevious_sibling) eq 'PPI::Token::Operator';
            }
            if ($next_op) {
                if ($next_op->content eq '=' ) {
                    push @{$doc->{tags}}, 'in:statement:variable:defined';
                }
                if ($next_op->content =~ /=/ ) { # += -= ~= //= ||=
                    push @{$doc->{tags}}, 'variable:lvalue';
                }
            }
            if ($prev_op) {
                if ($prev_op->content =~ /=/ ) { # += -= ~= //= ||= =
                    push @{$doc->{tags}}, 'variable:rvalue';
                }
            }
        }
        push @doc, $doc;

        #extract in-string variable
        if (ref($x) eq 'PPI::Token::Quote::Double') {
            #remove the quotation marks
            my $in_string_content = substr $x->content, 1, -1;
            my $in_string_ppi_doc = PPI::Document->new( \$in_string_content );
            if (defined($in_string_ppi_doc)) {
                for my $y ( $in_string_ppi_doc->tokens ) {
                    next unless $y->significant;
                    if ( ref($y) eq 'PPI::Token::Symbol' ) {
                        my $doc_t = dclone $doc;
                        $doc_t->{content} = $y->content;
                        $doc_t->{class} = $y->class;
                        push @{$doc_t->{tags}}, (
                            'symbol:actual='    . $y->symbol,
                            'symbol:canonical=' . $y->canonical
                        );
                        push @{$doc_t->{tags}}, 'variable:in-string';
                        push @doc, $doc_t;
                    }
                }
            }
        }
    }


    return @doc;
}

sub fleshen_scope_locations {
    my ($doc, $ppi_element) = @_;
    my @loc;
    my $scope_doc = $doc->{scope} //= [];

    my $el = $ppi_element;
    while ($el) {
        if ($el->scope) {
            my $loc_begin = $el->location;
            my $loc_end   = $el->last_element->location;
            push @$scope_doc, {
                tag   => join(",", $loc_begin->[0], $loc_begin->[1], $loc_end->[0], $loc_end->[1]),
                begin => TypeLineColumn($loc_begin),
                end   => TypeLineColumn($loc_end),
            }
        }
        $el = $el->parent;
    }
    return \@loc;
}

1;
