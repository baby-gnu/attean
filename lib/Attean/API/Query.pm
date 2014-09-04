use v5.14;
use warnings;

package Attean::API::DirectedAcyclicGraph 0.001 {
	use Moo::Role;
	use Scalar::Util qw(refaddr);
	use Types::Standard qw(ArrayRef ConsumerOf);
	has 'children' => (
		is => 'ro',
		isa => ArrayRef[ConsumerOf['Attean::API::DirectedAcyclicGraph']],
		default => sub { [] },
	);
	
	sub is_leaf {
		my $self	= shift;
		return not(scalar(@{ $self->children }));
	}
	
	sub walk {
		my $self	= shift;
		my %cb		= @_;
		if (my $cb = $cb{ prefix }) {
			$cb->( $self );
		}
		foreach my $c (@{ $self->children }) {
			$c->walk( %cb );
		}
		if (my $cb = $cb{ postfix }) {
			$cb->( $self );
		}
	}
	
	sub cover {
		my $self	= shift;
		return $self->_cover({}, @_);
	}
	
	sub _cover {
		my $self	= shift;
		my $seen	= shift;
		my %cb		= @_;
		return if ($seen->{refaddr($self)}++);
		if (my $cb = $cb{ prefix }) {
			$cb->( $self );
		}
		foreach my $c (@{ $self->children }) {
			$c->_cover( $seen, %cb );
		}
		if (my $cb = $cb{ postfix }) {
			$cb->( $self );
		}
	}
}

package Attean::API::Algebra 0.001 {
	use Moo::Role;
	
	sub BUILD {}
	if ($ENV{ATTEAN_TYPECHECK}) {
		around 'BUILD' => sub {
			my $orig	= shift;
			my $self	= shift;
			$self->$orig(@_);
			my $name	= ref($self);
			$name		=~ s/^.*://;
			if ($self->can('arity')) {
				my $arity	= $self->arity;
				my $children	= $self->children;
				my $size	= scalar(@$children);
				unless ($size == $arity) {
					die "${name} algebra construction with bad number of children (expected $arity, but got $size)";
				}
			}
		}
	}
}

package Attean::API::QueryTree 0.001 {
	use Moo::Role;
	with 'Attean::API::DirectedAcyclicGraph';
# TODO:
# 	requires 'in_scope_variables';
# 	requires 'necessarily_bound_variables';
# 	requires 'required_variables';			# assert required_variables ⊆ union(child->in_scope_variables)
}

package Attean::API::NullaryQueryTree {
	use Moo::Role;
	sub arity { return 0 }
	with 'Attean::API::QueryTree';
}

package Attean::API::UnaryQueryTree {
	use Moo::Role;
	sub arity { return 1 }
	with 'Attean::API::QueryTree';
}

package Attean::API::BinaryQueryTree {
	use Moo::Role;
	sub arity { return 2 }
	with 'Attean::API::QueryTree';
}

package Attean::API::PropertyPath 0.001 {
	use Moo::Role;
	with 'Attean::API::Algebra';
	with 'Attean::API::QueryTree';
	requires 'as_string';
}

package Attean::API::UnaryPropertyPath {
	use Moo::Role;
	use Types::Standard qw(ConsumerOf);
	sub arity { return 1 }
# 	has 'path' => (is => 'ro', isa => ConsumerOf['Attean::API::PropertyPath'], required => 1);
	sub prefix_name { "" }
	sub postfix_name { "" }
	sub as_string {
		my $self	= shift;
		my ($path)	= @{ $self->children };
		my $pstr	= $path->as_string;
		if ($path->does('Attean::API::UnaryPropertyPath')) {
			$pstr	= "($pstr)";
		}
		my $str	= sprintf("%s%s%s", $self->prefix_name, $pstr, $self->postfix_name);
		return $str;
	}
	with 'Attean::API::PropertyPath', 'Attean::API::UnaryQueryTree';
}

package Attean::API::NaryPropertyPath {
	use Moo::Role;
	use Types::Standard qw(ArrayRef ConsumerOf);
# 	has 'children' => (is => 'ro', isa => ArrayRef[ConsumerOf['Attean::API::PropertyPath']], required => 1);
	requires 'separator';
	sub as_string {
		my $self	= shift;
		my @children	= @{ $self->children };
		if (scalar(@children) == 1) {
			return $children[0]->as_string;
		} else {
			return sprintf("(%s)", join($self->separator, map { $_->as_string } @children));
		}
	}
	with 'Attean::API::PropertyPath';
}

1;
