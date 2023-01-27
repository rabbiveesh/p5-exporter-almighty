=pod

=encoding utf-8

=head1 PURPOSE

Unit tests for L<Exporter::Almighty>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2023 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use Test2::V0 -target => 'Exporter::Almighty';
use Test2::Tools::Spec;
use Data::Dumper;

use if $] lt '5.036000',
	'builtins::compat' => qw( is_bool created_as_string created_as_number );
use if $] ge '5.036000',
	'builtin'          => qw( is_bool created_as_string created_as_number );

use FindBin qw( $Bin );
use lib "$Bin/../../lib";

describe "class `$CLASS`" => sub {

	tests 'it is an Exporter::Tiny' => sub {
		isa_ok( $CLASS, 'Exporter::Tiny' );
	};
};

describe "method `base_exporter`" => sub {

	tests 'it returns Exporter::Tiny or a subclass of it' => sub {
		isa_ok( $CLASS->base_exporter, 'Exporter::Tiny' );
	};
};

describe "method `standard_package_variables`" => sub {

	{
		package Local::TestPkg1;
		our @ISA          = qw( strict );
		our @EXPORT       = qw( a b c );
		our @EXPORT_OK    = qw( d e f );
		our %EXPORT_TAGS  = ( xyz => [ 1, 2, 3 ] );
	}
	
	tests 'it works' => sub {
		
		is(
			[ $CLASS->standard_package_variables( 'Local::TestPkg1' ) ],
			array {
				item array {
					item string 'strict';
					end;
				};
				item array {
					item string 'a';
					item string 'b';
					item string 'c';
					end;
				};
				item array {
					item string 'd';
					item string 'e';
					item string 'f';
					end;
				};
				item hash {
					field xyz => array {
						item number 1;
						item number 2;
						item number 3;
						end;
					};
					end;
				};
				end;
			},
			'returns correct data',
		);
		
		my ( @vars ) = $CLASS->standard_package_variables( 'Local::TestPkg1' );
		$vars[3]{abc} = 99;
		is(
			$Local::TestPkg1::EXPORT_TAGS{abc},
			number( 99 ),
			'references package variables correctly',
		);
		delete $vars[3]{abc};
	};
};

describe "method `setup_for`" => sub {
	
	my ( $into, $setup, $inc_key, $expected_calls );
	
	case 'when no optional calls are needed' => sub {
		$into            = 'Local::TestPkg2';
		$setup           = {};
		$inc_key         = 'Local/TestPkg2.pm';
		$expected_calls  = 'XZ';
	};
	
	case 'when setup_reexports_for needs to be called' => sub {
		$into            = 'Local::TestPkg3';
		$setup           = { also => [] };
		$inc_key         = 'Local/TestPkg3.pm';
		$expected_calls  = 'XRZ';
	};
	
	case 'when setup_enums_for needs to be called' => sub {
		$into            = 'Local::TestPkg4';
		$setup           = { enum => {} };
		$inc_key         = 'Local/TestPkg4.pm';
		$expected_calls  = 'XEZ';
	};
	
	case 'when setup_constants_for needs to be called' => sub {
		$into            = 'Local::TestPkg5';
		$setup           = { const => {} };
		$inc_key         = 'Local/TestPkg5.pm';
		$expected_calls  = 'XCZ';
	};
	
	case 'when all optional calls are needed' => sub {
		$into            = 'Local::TestPkg6';
		$setup           = { also => [], const => {}, enum => {} };
		$inc_key         = 'Local/TestPkg6.pm';
		$expected_calls  = match qr/\AX(CER|CRE|ECR|ERC|RCE|REC)Z\z/;
	};
	
	tests 'it works' => sub {
		
		my $calls = '';
		my $guard = mock( $CLASS, override => [
			setup_exporter_for            => sub { $calls .= 'X' },
			setup_reexports_for           => sub { $calls .= 'R' },
			setup_enums_for               => sub { $calls .= 'E' },
			setup_constants_for           => sub { $calls .= 'C' },
			finalize_export_variables_for => sub { $calls .= 'Z' },
		] );
		
		$CLASS->setup_for( $into, $setup );
		
		is( $calls, $expected_calls, 'called other methods in expected order' );
		ok( $INC{$inc_key}, 'set key in %INC' );
	};
};

describe "method `setup_exporter_for`" => sub {

	my ( $into, $setup, $tags_var, $expected_tags );
	
	case 'when given one simple tag' => sub {
		$into           = 'Local::TestPkg7';
		$setup          = { tag => { 'foo' => [ 'abc', 'def' ] } };
		$tags_var       = \%Local::TestPkg7::EXPORT_TAGS;
		$expected_tags  = { 'foo' => [ 'abc', 'def' ] };
	};
	
	case 'when given a hyphen-prefixed tag' => sub {
		$into           = 'Local::TestPkg8';
		$setup          = { tag => { '-foo' => [ 'abc', 'def' ] } };
		$tags_var       = \%Local::TestPkg8::EXPORT_TAGS;
		$expected_tags  = { 'foo' => [ 'abc', 'def' ] };
	};
	
	case 'when given a colon-prefixed tag' => sub {
		$into           = 'Local::TestPkg9';
		$setup          = { tag => { ':foo' => [ 'abc', 'def' ] } };
		$tags_var       = \%Local::TestPkg9::EXPORT_TAGS;
		$expected_tags  = { 'foo' => [ 'abc', 'def' ] };
	};
	
	case 'when given two tags' => sub {
		$into           = 'Local::TestPkg10';
		$setup          = { tag => { ':foo' => [ 'abc', 'def' ], '-bar' => [ 'ghi' ] } };
		$tags_var       = \%Local::TestPkg10::EXPORT_TAGS;
		$expected_tags  = { 'foo' => [ 'abc', 'def' ], 'bar' => [ 'ghi' ] };
	};
	
	case 'when given no tags at all' => sub {
		$into           = 'Local::TestPkg11';
		$setup          = {};
		$tags_var       = \%Local::TestPkg11::EXPORT_TAGS;
		$expected_tags  = {};
	};
	
	tests 'it works' => sub {
		$CLASS->setup_exporter_for( $into, $setup );
		isa_ok( $into, 'Exporter::Tiny' );
		is( $tags_var, $expected_tags, '%EXPORT_TAGS correct' )
			or diag Dumper( $tags_var );
	};
};

describe "method `setup_exporter_for`" => sub {
	
	tests 'it works' => sub {
		
		$CLASS->setup_reexports_for(
			'Local::TestPkg12',
			{ also => [ 'Local::Dummy', [ 'xxx' ] ] },
		);
		
		ok(
			defined &Local::TestPkg12::_exporter_validate_opts,
			'defined _exporter_validate_opts',
		);
		
		ok(
			defined( &Local::Dummy::xxx )
				&& Local::Dummy->isa( 'Exporter::Tiny' )
				&& $Local::Dummy::EXPORT_OK[0] eq 'xxx',
			'Loaded Local::Dummy properly',
		);
		
		Local::TestPkg12->_exporter_validate_opts( {
			into => 'Local::TestPkg13',
		} );
		
		is(
			Local::TestPkg13::xxx(),
			123456,
			'_exporter_validate_opts works as it should',
		);
	};
};

describe "method `setup_enums_for`" => sub {
	
	tests 'it works' => sub {
		
		$CLASS->setup_enums_for(
			'Local::TestPkg14',
			{ enum => { Colour => [ qw/ red green blue / ] } },
		);
		
		is(
			Local::TestPkg14::Colour(),
			object {
				prop isa => 'Type::Tiny';
				prop isa => 'Type::Tiny::Enum';
				call values => bag {
					item string 'red';
					item string 'green';
					item string 'blue';
					end;
				};
			},
			'Colour()',
		);
		
		ok( Local::TestPkg14::is_Colour( 'red' ), 'is_Colour( "red" )' );
		ok( !Local::TestPkg14::is_Colour( 'banana' ), '!is_Colour( "banana" )' );
		
		is( Local::TestPkg14::COLOUR_BLUE(), 'blue', 'COLOUR_BLUE()' );
		
		is(
			\%Local::TestPkg14::EXPORT_TAGS,
			hash {
				field colour => bag {
					item string 'Colour';
					item string 'assert_Colour';
					item string 'is_Colour';
					item string 'to_Colour';
					item string 'COLOUR_RED';
					item string 'COLOUR_GREEN';
					item string 'COLOUR_BLUE';
					end;
				};
				field types => bag {
					item string 'Colour';
					end;
				};
				field assert => bag {
					item string 'assert_Colour';
					end;
				};
				field is => bag {
					item string 'is_Colour';
					end;
				};
				field to => bag {
					item string 'to_Colour';
					end;
				};
				field constants => bag {
					item string 'COLOUR_RED';
					item string 'COLOUR_GREEN';
					item string 'COLOUR_BLUE';
					end;
				};
				end;
			},
			'%EXPORT_TAGS',
		) or diag Dumper( \%Local::TestPkg14::EXPORT_TAGS );
	};
};

describe "method `setup_constants_for`" => sub {
	
	tests 'it works' => sub {
		
		my $ref = {};
		$CLASS->setup_constants_for(
			'Local::TestPkg15',
			{ const => {
				colours => { RED => 'r', GREEN => 'g', BLUE => 'b' },
				things  => { STRINGY => "1", NUMMY => 1, BOOLY => !!1, REFFY => $ref },
			} },
		);
		
		is( Local::TestPkg15::RED(), 'r', 'RED()' );
		is( Local::TestPkg15::GREEN(), 'g', 'GREEN()' );
		is( Local::TestPkg15::BLUE(), 'b', 'BLUE()' );
		
		ok(
			created_as_string( Local::TestPkg15::STRINGY() ),
			'string constants',
		);
		
		ok(
			created_as_number( Local::TestPkg15::NUMMY() ),
			'numeric constants',
		);
		
		ok(
			is_bool( Local::TestPkg15::BOOLY() ),
			'boolean constants',
		);
		
		Local::TestPkg15::REFFY()->{abc} = 1;
		is(
			$ref,
			{ abc => 1 },
			'reference constants',
		);
		
		is(
			\%Local::TestPkg15::EXPORT_TAGS,
			hash {
				field colours => bag {
					item string 'RED';
					item string 'GREEN';
					item string 'BLUE';
					end;
				};
				field things => bag {
					item string 'STRINGY';
					item string 'NUMMY';
					item string 'BOOLY';
					item string 'REFFY';
					end;
				};
				field constants => bag {
					item string 'RED';
					item string 'GREEN';
					item string 'BLUE';
					item string 'STRINGY';
					item string 'NUMMY';
					item string 'BOOLY';
					item string 'REFFY';
					end;
				};
				end;
			},
			'%EXPORT_TAGS',
		) or diag Dumper( \%Local::TestPkg15::EXPORT_TAGS );
	};
};

describe "method `make_constant_subs`" => sub {
	
	tests 'it works' => sub {
		
		my $ref = {};
		$CLASS->make_constant_subs(
			'Local::TestPkg16',
			{ STRINGY => "1", NUMMY => 1, BOOLY => !!1, REFFY => $ref },
		);
		
		ok(
			created_as_string( Local::TestPkg16::STRINGY() ),
			'string constants',
		);
		
		ok(
			created_as_number( Local::TestPkg16::NUMMY() ),
			'numeric constants',
		);
		
		ok(
			is_bool( Local::TestPkg16::BOOLY() ),
			'boolean constants',
		);
		
		Local::TestPkg16::REFFY()->{abc} = 1;
		is(
			$ref,
			{ abc => 1 },
			'reference constants',
		);
	};
};


describe "method `make_constant_subs`" => sub {
	
	tests 'it works' => sub {
		
		%Local::TestPkg17::EXPORT_TAGS = (
			foo     => [ 'foo1', 'foo2' ],
			bar     => [ 'bar1', 'bar2' ],
			foobar1 => [ 'foo1', 'bar1' ],
			default => [ 'xxx' ],
		);
		
		$CLASS->finalize_export_variables_for( 'Local::TestPkg17', {} );
		
		is(
			\@Local::TestPkg17::EXPORT_OK,
			bag {
				item string 'foo1';
				item string 'foo2';
				item string 'bar1';
				item string 'bar2';
				item string 'xxx';
				end;
			},
			'@EXPORT_OK',
		) or diag Dumper( \@Local::TestPkg17::EXPORT_OK );
		
		is(
			\@Local::TestPkg17::EXPORT,
			bag {
				item string 'xxx';
				end;
			},
			'@EXPORT',
		) or diag Dumper( \@Local::TestPkg17::EXPORT );
	};
};


done_testing;
