package P5iq::Analyzer;
use strict;
use warnings;

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
            extract_subroutine($ppi_doc),
            extract_function_calls($ppi_doc),
            extract_method_calls($ppi_doc),
            extract_package($ppi_doc),
        ],
        p5_statement => [
            extract_package_dependency($ppi_doc),
            extract_statements($ppi_doc)
        ]
    }
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
        push @doc, {
            class         => "P5iq::PackageDependency",
            content       => $p,
            token_content => \@deps,
        };
    }

    return @doc;
}

sub extract_statements {
    my ($ppi_doc) = @_;
    my @doc;
    my $statements = $ppi_doc->find(sub { $_[1]->isa('PPI::Statement') });
    for my $s (@$statements) {
        my $location = $s->location;
        my @tokens = grep { $_->significant } $s->tokens;
        push @doc, {
            line_number => $location->[0],
            class         => $s->class,
            token_content => [ map { $_->content } @tokens ],
            token_class   => [ map { $_->class   } @tokens ],
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
            line_number   => $el->location->[0],
            row_number    => $el->location->[1],
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
            line_number   => $el->location->[0],
            row_number    => $el->location->[1],
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

        my @ctxt;
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            last if !$p->isa('PPI::Token') || $p->isa('PPI::Token::Operator') && $p->content ne '->';
            last if @ctxt && $p->isa('PPI::Token::Word') && !$ctxt[0]->isa('PPI::Token::Operator');
            unshift(@ctxt, $p);
        }

        my $context = @ctxt ? join("", @ctxt) : "???";

        my $args = $method->snext_sibling;
        $args = (ref($args) eq 'PPI::Structure::List') ? $args->content : "";

        push @doc, {
            line_number   => $method->location->[0],
            row_number    => $method->location->[1],
            content       => join("", "$context", "->", "$method", "$args"),
            class         => 'P5iq::MethodCall',
            tags          => [
                "subroutine:call",
                "subroutine:name=$method",
                "subroutine:arglist=$args",
                "method:call",
                "method:name=$method",
                "method:context=$context",
                "method:arglist=$args"
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

        my (@ns) = split(/::/, "$s");
        my $name = pop(@ns);
        my $namespace = join("::", @ns);
        push @doc, {
            line_number   => $s->location->[0],
            row_number    => $args->location->[1],
            content       => join("", "$s", "$args"),
            class         => 'P5iq::FunctionCall',
            tags          => [
                "subroutine:call",
                "subroutine:name=$name",
                "subroutine:namespace=$namespace",
                "subroutine:arglist=$args",
                "function:call",
                "function:name=$s",
                "function:arglist=$args"
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
        my @c = ( $s );
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            unshift @c, $p;
            last if $p->isa("PPI::Token::Symbol");
        }
        my $location = $c[0]->location;
        my $doc = {
            line_number   => $location->[0],
            row_number    => $location->[1],
            content       => join("", @c),
            class         => 'PPI::Structure::Subscript',
            token_content => [map { $_->content } @c],
            token_class   => [map { $_->class }   @c],
            tags          => [
                "subscript:symbol=$c[0]",
                "subscript:container=" . join("", map { $_->content } @c[0..$#c-1] ),
                "subscript:content=$s",
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
        my $location = $x->location;
        my $doc = {
            content  => $x->content,
            class    => $x->class,
            tags     => [],
            scope    => [],
            location => {
                line => $location->[0],
                column => $location->[0],
            }
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
                begin => {
                    tag   => join(",", $loc_begin->[0], $loc_begin->[1]),
                    line => $loc_begin->[0],
                    column => $loc_begin->[1],
                },
                end   => {
                    tag  => join(",", $loc_end->[0], $loc_end->[1]),
                    line => $loc_end->[0],
                    column => $loc_end->[1],
                }
            }
        }
        $el = $el->parent;
    }
    return \@loc;
}

1;
