use v5.14;
use warnings;

package RDF::Literal 0.001 {
	use RDF::API::Term;
	use Moose;
	use IRI;
	
	has 'ntriples_string'	=> (is => 'ro', isa => 'Str', lazy => 1, builder => '_ntriples_string');

	with 'RDF::API::Literal';

	around BUILDARGS => sub {
		my $orig 	= shift;
		my $class	= shift;
		if (scalar(@_) == 1) {
			my $dt	= IRI->new('http://www.w3.org/2001/XMLSchema#string');
			return $class->$orig(value => shift, datatype => $dt);
		}
		
		my %args	= @_;
		return $class->$orig(%args);
	};
	
	sub BUILD {
		my $self	= shift;
		die unless ($self->has_language or length($self->datatype->as_string));
	}
	
	around 'datatype'	=> sub {
		my $orig	= shift;
		my $self	= shift;
		if ($self->has_language) {
			return IRI->new(value => 'http://www.w3.org/2001/XMLSchema#string');
		} else {
			return $self->$orig(@_);
		}
	};
	
	sub _ntriples_string {
		my $self	= shift;
		my $value	= $self->value;
		$value		=~ s/\\/\\\\/g;
		$value		=~ s/\n/\\n/g;
		$value		=~ s/\r/\\r/g;
		$value		=~ s/"/\\"/g;
		if ($self->has_language) {
			return sprintf('"%s"@%s', $value, $self->language);
		} else {
			my $dt	= $self->datatype->as_string;
			if ($dt eq 'http://www.w3.org/2001/XMLSchema#string') {
				return sprintf('"%s"', $self->value);
			} else {
				return sprintf('"%s"^^<%s>', $value, $dt);
			}
		}
	}
}

1;