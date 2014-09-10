use Test::More;
use Test::Exception;

use v5.14;
use warnings;
no warnings 'redefine';

use Attean;
use Attean::RDF;

{
	my $parser	= Attean->get_parser('Turtle')->new();
	my $store	= Attean->get_store('Memory')->new();
	my $model	= Attean::MutableQuadModel->new( store => $store );
	
	my $graph	= Attean::IRI->new('http://example.org/graph');
	{
		my $data	= <<"END";
		_:a <b> _:a .
		<a> <b> <a> .
		<a> <c> 2, 3 .
END
		my $iter	= $parser->parse_iter_from_bytes($data);
		my $quads	= $iter->as_quads($graph);
		$store->add_iter($quads);
	}
	
	my $e	= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $graph );
	isa_ok($e, 'Attean::SimpleQueryEvaluator');
	
	my $active_graph	= $graph;

	{
		my $t	= Attean::TriplePattern->new(map { variable($_) } qw(s p o));
		my $bgp	= Attean::Algebra::BGP->new( triples => [$t] );
		does_ok($bgp, 'Attean::API::Algebra');
	
		my $iter	= $e->evaluate($bgp, $active_graph);
		my $count	= 0;
		while (my $r = $iter->next) {
			$count++;
			does_ok($r, 'Attean::API::Result');
			my $s	= $r->value('s');
			is($s->value, 'a');
			my $p	= $r->value('p');
			does_ok($p, 'Attean::API::IRI');
			like($p->value, qr/^[bc]$/);
		}
		is($count, 4);
	}

	{
		my $t1	= Attean::TriplePattern->new(iri('a'), iri('b'), variable('o1'));
		my $t2	= Attean::TriplePattern->new(iri('a'), iri('c'), variable('o2'));
		my $bgp	= Attean::Algebra::BGP->new( triples => [$t1, $t2] );
		does_ok($bgp, 'Attean::API::Algebra');
	
		my $iter	= $e->evaluate($bgp, $active_graph);
		my $count	= 0;
		while (my $r = $iter->next) {
			$count++;
			like($r->as_string, qr[{o1=<a>, o2="[23]"\^\^<http://www.w3.org/2001/XMLSchema#integer>}]);
		}
		is($count, 2);
	}
}

{
	my $g		= iri('g');
	my $parser	= Attean->get_parser('NQuads')->new();
	my $store	= Attean->get_store('Memory')->new();
	my $model	= Attean::MutableQuadModel->new( store => $store );
	{
		my $data	= <<"END";
		<a> <p> <b> <g> .
		<b> <p> <c> <g> .
		<c> <p> <d> <g> .
		<c> <q> <e> <g> .
		
		<b> <values> "0"^^<http://www.w3.org/2001/XMLSchema#integer> <ints> .
		<b> <values> "1"^^<http://www.w3.org/2001/XMLSchema#integer> <ints> .
		<b> <values> "2"^^<http://www.w3.org/2001/XMLSchema#integer> <ints> .
		<b> <values> "07"^^<http://www.w3.org/2001/XMLSchema#integer> <ints> .
END
		my $iter	= $parser->parse_iter_from_bytes($data);
		$store->add_iter($iter->as_quads($g));
	}
	
	{
		note('Project');
		my $t		= triplepattern(variable('s'), iri('q'), variable('o'));
		my $b		= Attean::Algebra::BGP->new( triples => [$t] );
		my $p		= Attean::Algebra::Project->new( children => [$b], variables => [variable('s')] );
		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my $iter	= $e->evaluate($p, $g);
		my @subj	= $iter->elements;
		is(scalar(@subj), 1, 'expected project count');
		my ($r)		= @subj;
		does_ok($r, 'Attean::API::Result');
		is_deeply([$r->variables], ['s'], 'expected projection variable');
	}
	
	{
		note('Distinct');
		my $t		= triplepattern(variable('s'), variable('p'), variable('o'));
		my $b		= Attean::Algebra::BGP->new( triples => [$t] );
		my $p		= Attean::Algebra::Project->new( children => [$b], variables => [variable('p')] );
		my $d		= Attean::Algebra::Distinct->new( children => [$p] );
		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );

		my $proj	= $e->evaluate($p, $g);
		my @ppreds	= $proj->elements;
		is(scalar(@ppreds), 4, 'pre-distinct projected count');
		
		my $dist	= $e->evaluate($d, $g);
		my @dpreds	= $dist->elements;
		is(scalar(@dpreds), 2, 'post-distinct projected count');

		my %preds	= map { $_->value('p')->value => 1 } @dpreds;
		is_deeply(\%preds, { 'p' => 1, 'q' => 1 });
	}

	{
		note('Filter');
		my $t		= triplepattern(variable('s'), variable('p'), variable('o'));
		my $bgp		= Attean::Algebra::BGP->new( triples => [$t] );
		my $expr	= Attean::ValueExpression->new( value => variable('o') );
		my $f		= Attean::Algebra::Filter->new( children => [$bgp], expression => $expr );

		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my $iter	= $e->evaluate($f, iri('ints'));
		my @quads	= $iter->elements;
		is(scalar(@quads), 3, 'filter count');
		
		my @values	= sort { $a <=> $b } map { 0+($_->value('o')->value) } @quads;
		is_deeply(\@values, [1, 2, 7]);
	}

	{
		note('IRI Graph');
		my $t		= triplepattern(variable('s'), iri('values'), variable('o'));
		my $bgp		= Attean::Algebra::BGP->new( triples => [$t] );
		my $graph	= Attean::Algebra::Graph->new( children => [$bgp], graph => iri('ints') );

		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my $iter	= $e->evaluate($graph, $g);
		my @quads	= $iter->elements;
		is(scalar(@quads), 4, 'graph count');
		
		my @values	= sort { $a <=> $b } map { 0+($_->value('o')->value) } @quads;
		is_deeply(\@values, [0, 1, 2, 7]);
	}

	{
		note('Variable Graph');
		my $t		= triplepattern(variable('s'), iri('values'), variable('o'));
		my $bgp		= Attean::Algebra::BGP->new( triples => [$t] );
		my $graph	= Attean::Algebra::Graph->new( children => [$bgp], graph => variable('graph') );

		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my $iter	= $e->evaluate($graph, $g);
		my @quads	= $iter->elements;
		is(scalar(@quads), 4, 'graph count');
		
		my ($r)		= @quads;
		does_ok($r, 'Attean::API::Result');
		my $gt		= $r->value('graph');
		does_ok($gt, 'Attean::API::Term');
		is($gt->value, 'ints');
	}

	{
		note('Join');
		my $t1		= triplepattern(iri('a'), iri('p'), variable('o'));
		my $bgp1	= Attean::Algebra::BGP->new( triples => [$t1] );

		my $t2		= triplepattern(variable('o'), iri('p'), iri('c'));
		my $bgp2	= Attean::Algebra::BGP->new( triples => [$t2] );
		
		my $j		= Attean::Algebra::Join->new( children => [$bgp1, $bgp2] );
		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my $iter	= $e->evaluate($j, $g);
		my @results	= $iter->elements;
		is(scalar(@results), 1, 'expected result count');
		my ($r)		= @results;
		does_ok($r, 'Attean::API::Result');
		my $term	= $r->value('o');
		is($term->value, 'b');
	}

	{
		note('Slice');
		my $t		= triplepattern(variable('s'), variable('p'), variable('o'));
		my $b		= Attean::Algebra::BGP->new( triples => [$t] );
		my $s_o		= Attean::Algebra::Slice->new( children => [$b], offset => 1 );
		my $s_l		= Attean::Algebra::Slice->new( children => [$b], limit => 1 );
		my $s_ol	= Attean::Algebra::Slice->new( children => [$b], limit => 1, offset => 1 );
		
		my $e		= Attean::SimpleQueryEvaluator->new( model => $model, default_graph => $g );
		my @r_o		= $e->evaluate($s_o, $g)->elements;
		my @r_l		= $e->evaluate($s_l, $g)->elements;
		my @r_ol	= $e->evaluate($s_ol, $g)->elements;
		is(scalar(@r_o), 3, 'offset count');
		is(scalar(@r_l), 1, 'limit count');
		is(scalar(@r_ol), 1, 'offset/limit count');
	}
	
}

done_testing();


sub does_ok {
    my ($class_or_obj, $does, $message) = @_;
    $message ||= "The object does $does";
    ok(eval { $class_or_obj->does($does) }, $message);
}