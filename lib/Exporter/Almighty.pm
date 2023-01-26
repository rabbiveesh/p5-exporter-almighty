use 5.012;
use strict;
use warnings;

package Exporter::Almighty;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.001000';

use parent           qw( Exporter::Tiny );

use builtins::compat qw( is_bool created_as_string created_as_number );
use B                qw( perlstring );
use Carp             qw( croak );
use Eval::TypeTiny   qw( eval_closure set_subname );
use Exporter::Tiny   qw( mkopt );
use Import::Into;
use Module::Runtime  qw( require_module module_notional_filename );
use Type::Registry   qw();
use Type::Tiny::Enum qw();
use Types::Common    qw(
	-sigs
	-types
	assert_Ref       is_Ref
	assert_ArrayRef  is_ArrayRef
	assert_HashRef   is_HashRef
	is_NonEmptySimpleStr
);

sub _exporter_validate_opts {
	my ( $me, $options ) = @_;
	my $into  = $options->{into};
	my $setup = $options->{setup};
	strict->import::into( $into );
	warnings->import::into( $into );
	$me->setup_for( $into, $setup );
}

sub base_exporter {
	return 'Exporter::Tiny';
}

sub standard_package_variables {
	my ( $me, $into ) = @_;
	no strict 'refs';
	return (
		\@{"$into\::ISA"},
		\@{"$into\::EXPORT"},
		\@{"$into\::EXPORT_OK"},
		\%{"$into\::EXPORT_TAGS"},
	);
}

signature_for setup_for => (
	method     => 1,
	positional => [
		NonEmptySimpleStr,
		Dict[
			tag    => Optional[HashRef],
			const  => Optional[HashRef],
			enum   => Optional[HashRef[ArrayRef]],
			also   => Optional[ArrayRef],
		],
	],
);

sub setup_for {
	my ( $me, $into, $setup ) = @_;
	$INC{ module_notional_filename($into) } //= __FILE__;
	$me->setup_exporter_for( $into, $setup );
	$me->setup_reexports_for( $into, $setup )  if $setup->{also};
	$me->setup_enums_for( $into, $setup )      if $setup->{enum};
	$me->setup_constants_for( $into, $setup )  if $setup->{const};
	$me->finalize_export_variables_for( $into, $setup );
	return;
}

sub setup_exporter_for {
	my ( $me, $into, $setup ) = @_;
	
	my ( $into_ISA, undef, undef, $into_EXPORT_TAGS ) =
		$me->standard_package_variables( $into );
	
	# Set up @ISA in caller package.
	push @$into_ISA, $me->base_exporter;
	
	# Set up %EXPORT_TAGS in caller package.
	my %tags = %{ $setup->{tag} // {} };
	for my $tag_name ( keys %tags ) {
		my @exports = @{ assert_ArrayRef $tags{$tag_name} };
		$tag_name =~ s/^[-:]//;
		push @{ $into_EXPORT_TAGS->{$tag_name} //= [] }, @exports;
	}
	
	return;
}

sub setup_reexports_for {
	my ( $me, $into, $setup ) = @_;
	
	my $optlist = mkopt( $setup->{also} );
	require_module( $_->[0] ) for @$optlist;
	
	my $method_name = "$into\::_exporter_validate_opts";
	my $method_code = sub {
		my ( $class, $opts ) = @_;
		is_NonEmptySimpleStr( my $caller = $opts->{into} ) or return;
		for my $also ( @$optlist ) {
			my ( $module, $args ) = @$also;
			$module->import::into( $caller, @{ $args // [] } );
		}
	};
	no strict 'refs';
	*$method_name = set_subname $method_name => $method_code;
}

sub setup_enums_for {
	my ( $me, $into, $setup ) = @_;
	
	my ( $into_ISA, undef, undef, $into_EXPORT_TAGS ) =
		$me->standard_package_variables( $into );
	my $reg = Type::Registry->for_class( $into );
	
	my %tags = %{ assert_HashRef $setup->{enum} // {} };
	for my $tag_name ( keys %tags ) {
		my $values = $tags{$tag_name};
		$tag_name =~ s/^[-:]//;
		my $type_name = $tag_name;
		$tag_name = lc $tag_name;
		
		Type::Tiny::Enum->import( { into => $into }, $type_name, $values );
		my @exportables = @{ $reg->lookup( $type_name )->exportables };
		for my $e ( @exportables ) {
			for my $t ( @{ $e->{tags} } ) {
				push @{ $into_EXPORT_TAGS->{$t} //= [] }, $e->{name};
			}
		}
		push @{ $into_EXPORT_TAGS->{$tag_name} //= [] }, map $_->{name}, @exportables;
	}
	
	return;
}

sub setup_constants_for {
	my ( $me, $into, $setup ) = @_;
	
	my ( $into_ISA, undef, undef, $into_EXPORT_TAGS ) =
		$me->standard_package_variables( $into );

	my %tags = %{ assert_HashRef $setup->{const} // {} };
	for my $tag_name ( keys %tags ) {
		my %exports = %{ assert_HashRef $tags{$tag_name} };
		$tag_name =~ s/^[-:]//;
		push @{ $into_EXPORT_TAGS->{$tag_name}   //= [] }, sort keys %exports;
		push @{ $into_EXPORT_TAGS->{'constants'} //= [] }, sort keys %exports;
		$me->make_constant_subs( $into, \%exports );
	}
	
	return;
}

sub make_constant_subs {
	my ( $me, $into, $constants ) = @_;
	
	for my $key ( keys %$constants ) {
		my $value = $constants->{$key};
		my $full_name = "$into\::$key";
		
		my $coderef;
		if ( is_Ref $value ) {
			$coderef = eval_closure(
				source      => 'sub () { $value }',
				environment => { '$value' => \$value },
			);
		}
		else {
			$coderef = eval sprintf(
				'sub () { %s %s }',
				is_bool( $value ) ? '!!' : ( created_as_number( $value ) ? '0+' : '' ),
				perlstring( $value ),
			);
		}
		
		no strict 'refs';
		*$full_name = set_subname $full_name => $coderef;
	}
}

sub finalize_export_variables_for {
	my ( $me, $into, $setup ) = @_;
	
	my ( $into_ISA, $into_EXPORT, $into_EXPORT_OK, $into_EXPORT_TAGS ) =
		$me->standard_package_variables( $into );
	
	my %all_exports;
	for my $list ( $into_EXPORT, $into_EXPORT_OK, values %{ $into_EXPORT_TAGS // {} } ) {
		is_ArrayRef $list or next;
		$all_exports{$_}++ for @$list;
	}
	@{ $into_EXPORT_OK } = sort keys %all_exports;
	
	my %default_exports;
	for my $list ( $into_EXPORT, $into_EXPORT_TAGS->{default} ) {
		is_ArrayRef $list or next;
		$all_exports{$_}++ for @$list;
	}
	@{ $into_EXPORT } = sort keys %default_exports;
	
	return;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Exporter::Almighty - combining Exporter::Tiny with some other stuff for added power

=head1 SYNOPSIS

  package Your::Package;
  
  use Exporter::Almighty -setup => {
    tag => {
      foo => [ 'foo1', 'foo2' ],
      bar => [ 'bar1' ],
    },
    const => {
      colours => { RED => 'red', BLUE => 'blue', GREEN => 'green' },
    },
    enum => {
      Status => [ 'dead', 'alive' ],
    },
    also => [
      'strict',
      'Scalar::Util' => [ 'refaddr' ],
      'warnings',
    ],
  };
  
  sub foo1 { ... }
  sub foo2 { ... }
  sub bar1 { ... }
  
  1;

=head1 DESCRIPTION

This module aims to make building exporters easier. It is based on
L<Exporter::Shiny>, but helps you avoid manually setting C<< @EXPORT_OK >>,
C<< %EXPORT_TAGS >>, etc.

=head2 Setup Options

Exporter::Almighty's own setup happens through its import. A setup hashref
is passed as per the example in the L</SYNOPSIS>. Each key in this hash is
a setup option.

The names are all short, singular names, in case you forget whether to use
C<tag> or C<tags>!

=head3 C<< tag >>

This is a hashref where the keys are tag names and the values are arrayrefs
of function names.

A user of the package defined in the L</SYNOPSIS> could import:

  use Your::Package qw( foo1 foo2 bar1 );   # import functions by name
  use Your::Package qw( :foo );             # import 'foo1' and 'foo2'
  use Your::Package qw( -foo );             # same!

If you have a tag called C<default>, that is special. It will be
automatically exported if your caller doesn't provide an explicit
list of things they want to import.

The following other tags also have special meanings: C<constants>,
C<types>, C<assert>, C<is>, C<to>, and C<all>.

=head3 C<< const >>

Similar to C<< tag >> this is a hashref where keys are tag names, but instead
of the values being arrayrefs of function names, they are hashrefs which
define constants.

A user of the package defined in the L</SYNOPSIS> could import:

  use Your::Package qw( RED GREEN BLUE );   # import constants by name
  use Your::Package qw( :colours );         # import 'colours' constants
  use Your::Package qw( :constants );       # import ALL constants

=head3 C<< enum >>

This is a hashref where keys are enumerated type names, and the values are
arrayrefs of strings.

A user of the package defined in the L</SYNOPSIS> could import:

  use Your::Package qw(
    Status
    is_Status
    assert_Status
    to_Status
    STATUS_ALIVE
    STATUS_DEAD
  );
  use Your::Package qw( :status );          # shortcut for the above

The C<< :type >>, C<< :is >>, C<< :assert >>, C<< :to >>, and C<< :constants >>
tags will also automatically include the relevent exports.

=head3 C<< also >>

A list of other packages to also export to your caller. Each package name
can optionally be followed by an arrayerf of import arguments.

Your caller isn't given any options allowing them to opt in or out of this,
so it is recommended that this be used sparingly. L<strict>, L<warnings>,
L<feature>, L<experimental>, and L<namespace::autoclean> are good packages to
consider listing here. Packages that export named functions are less good.

=head2 Exporter::Tiny features you get for free

Your caller can do lexical imports:

  use Your::Package -lexical, qw( ... );

Your caller can rename imported functions:

  use Your::Package foo => { -as => 'foofoo' };

And everything else described in L<Exporter::Tiny::Manual::Importing>.

=head1 BUGS

Please report any bugs to
L<https://github.com/tobyink/p5-exporter-almighty/issues>.

=head1 SEE ALSO

L<Exporter::Tiny>, L<Exporter::Shiny>.

L<CXC::Exporter::Util> was an inspiration for this module and the features
overlap a bit.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2023 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

