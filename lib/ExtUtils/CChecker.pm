#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package ExtUtils::CChecker;

use strict;
use warnings;

our $VERSION = '0.02';

use Carp;

use ExtUtils::CBuilder;

=head1 NAME

C<ExtUtils::CChecker> - configure-time utilities for using C headers,
libraries, or OS features

=head1 SYNOPSIS

 use Module::Build;
 use ExtUtils::CChecker;

 my $check_PF_MOONLASER = <<'EOF';
 #include <stdio.h>
 #include <sys/socket.h>
 int main(int argc, char *argv[]) {
   printf("PF_MOONLASER is %d\n", PF_MOONLASER);
   return 0;
 }
 EOF

 ExtUtils::CChecker->new->assert_compile_run(
    diag => "no PF_MOONLASER",
    source => $check_PF_MOONLASER,
 );

 Module::Build->new(
   ...
 )->create_build_script;

=head1 DESCRIPTION

Often Perl modules are written to wrap functionallity found in existing C
headers, libraries, or to use OS-specific features. It is useful in the
F<Build.PL> or F<Makefile.PL> file to check for the existance of these
requirements before attempting to actually build the module.

Objects in this class provide an extension around L<ExtUtils::CBuilder> to
simplify the creation of a F<.c> file, compiling, linking and running it, to
test if a certain feature is present.

It may also be necessary to search for the correct library to link against,
or for the right include directories to find header files in. This class also
provides assistance here.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $cc = ExtUtils::CChecker->new

Returns a new instance of a C<ExtUtils::CChecker> object.

=cut

sub new
{
   my $class = shift;

   my $cb = ExtUtils::CBuilder->new( quiet => 1 );

   return bless {
      cb  => $cb,
      seq => 0,

      include_dirs         => [],
      extra_compiler_flags => [],
      extra_linker_flags   => [],
   }, $class;
}

=head1 METHODS

=cut

=head2 $dirs = $cc->include_dirs

Returns the currently-configured include directories in an ARRAY reference.

=cut

sub include_dirs
{
   my $self = shift;
   # clone it just so caller can't modify ours
   return [ @{ $self->{include_dirs} } ];
}

=head2 $flags = $cc->extra_compiler_flags

Returns the currently-configured extra compiler flags in an ARRAY reference.

=cut

sub extra_compiler_flags
{
   my $self = shift;
   # clone it just so caller can't modify ours
   return [ @{ $self->{extra_compiler_flags} } ];
}

=head2 $flags = $cc->extra_linker_flags

Returns the currently-configured extra linker flags in an ARRAY reference.

=cut

sub extra_linker_flags
{
   my $self = shift;
   # clone it just so caller can't modify ours
   return [ @{ $self->{extra_linker_flags} } ];
}

sub cbuilder
{
   my $self = shift;
   return $self->{cb};
}

sub compile
{
   my $self = shift;
   my %args = @_;

   $args{include_dirs} = [ map { defined $_ ? @$_ : () } $self->{include_dirs}, $args{include_dirs} ];
   $args{extra_compiler_flags} = [ map { defined $_ ? @$_ : () } $self->{extra_compiler_flags}, $args{extra_compiler_flags} ];

   $self->cbuilder->compile( %args );
}

sub link_executable
{
   my $self = shift;
   my %args = @_;

   $args{extra_linker_flags} = [ map { defined $_ ? @$_ : () } $self->{extra_linker_flags}, $args{extra_linker_flags} ];

   $self->cbuilder->link_executable( %args );
}

sub fail
{
   my $self = shift;
   my ( $diag ) = @_;

   my $message = defined $diag ? "OS unsupported - $diag\n" : "OS unsupported\n";
   die $message;
}

=head2 $success = $cc->try_compile_run( %args )

=head2 $success = $cc->try_compile_run( $source )

Try to complile, link, and execute a C program whose source is given. Returns
true if the program compiled and linked, and exited sucessfully. Returns false
if any of these steps fail.

Takes the following named arguments. If a single argument is given, that is
taken as the source string.

=over 8

=item * source => STRING

The source code of the C program to try compiling, building, and running.

=item * extra_compiler_flags => ARRAY

Optional. If specified, pass extra flags to the compiler.

=item * extra_linker_flags => ARRAY

Optional. If specified, pass extra flags to the linker.

=back

=cut

sub try_compile_run
{
   my $self = shift;
   my %args = ( @_ == 1 ) ? ( source => $_[0] ) : @_;

   defined $args{source} or croak "Expected 'source'";

   my $seq = $self->{seq}++;

   my $test_source = "test-$seq.c";

   open( my $test_source_fh, "> $test_source" ) or die "Cannot write $test_source - $!";

   print $test_source_fh $args{source};

   close $test_source_fh;

   my %compile_args = (
      source => $test_source,
   );

   $compile_args{include_dirs} = $args{include_dirs} if exists $args{include_dirs};
   $compile_args{extra_compiler_flags} = $args{extra_compiler_flags} if exists $args{extra_compiler_flags};

   my $test_obj = eval { $self->compile( %compile_args ) };

   unlink $test_source;

   if( not defined $test_obj ) {
      return 0;
   }

   my %link_args = (
      objects => $test_obj,
   );

   $link_args{extra_linker_flags} = $args{extra_linker_flags} if exists $args{extra_linker_flags};

   my $test_exe = eval { $self->link_executable( %link_args ) };

   unlink $test_obj;

   if( not defined $test_exe ) {
      return 0;
   }

   if( system( "./$test_exe" ) != 0 ) {
      unlink $test_exe;
      return 0;
   }

   unlink $test_exe;

   return 1;
}

=head2 $cc->assert_compile_run( %args )

Calls C<try_compile_run>. If it fails, die with an C<OS unsupported> message.
Useful to call from F<Build.PL> or F<Makefile.PL>.

Takes one extra optional argument:

=over 8

=item * diag => STRING

If present, this string will be appended to the failure message if one is
generated. It may provide more useful information to the user on why the OS is
unsupported.

=back

=cut

sub assert_compile_run
{
   my $self = shift;
   my %args = @_;

   my $diag = delete $args{diag};
   $self->try_compile_run( %args ) or $self->fail( $diag );
}

=head2 $cc->find_include_dirs_for( %args )

Try to compile, link and execute the given source, using extra include
directories.

When a usable combination is found, the directories required are stored in the
object for use in further compile operations, or returned by C<include_dirs>.

If no usable combination is found, an assertion message is thrown.

Takes the following arguments:

=over 8

=item * source => STRING

Source code to compile

=item * dirs => ARRAY of ARRAYs

Gives a list of sets of dirs. Each set of dirs should be strings in its own
array reference.

=item * diag => STRING

If present, this string will be appended to the failure message if one is
generated.

=back

=cut

sub find_include_dirs_for
{
   my $self = shift;
   my %args = @_;

   my $diag = delete $args{diag};

   ref( my $dirs = $args{dirs} ) eq "ARRAY" or croak "Expected 'dirs' as ARRAY ref";

   my @include_dirs;
   push @include_dirs, $args{include_dirs} if exists $args{include_dirs};

   foreach my $d ( @$dirs ) {
      ref $d eq "ARRAY" or croak "Expected 'dirs' element as ARRAY ref";

      $self->try_compile_run( %args, include_dirs => $d ) or next;

      push @{ $self->{include_dirs} }, @$d;
      return;
   }

   $self->fail( $diag );
}

=head2 $cc->find_libs_for( %args )

Try to compile, link and execute the given source, when linked against a
given set of extra libraries.

When a usable combination is found, the libraries required are stored in the
object for use in further link operations, or returned by
C<extra_linker_flags>.

If no usable combination is found, an assertion message is thrown.

Takes the following arguments:

=over 8

=item * source => STRING

Source code to compile

=item * libs => ARRAY of STRINGs

Gives a list of sets of libraries. Each set of libraries should be
space-separated.

=item * diag => STRING

If present, this string will be appended to the failure message if one is
generated.

=back

=cut

sub find_libs_for
{
   my $self = shift;
   my %args = @_;

   my $diag = delete $args{diag};

   ref( my $libs = $args{libs} ) eq "ARRAY" or croak "Expected 'libs' as ARRAY ref";

   foreach my $l ( @$libs ) {
      my @extra_linker_flags = map { "-l$_" } split m/\s+/, $l;

      $self->try_compile_run( %args, extra_linker_flags => \@extra_linker_flags ) or next;

      push @{ $self->{extra_linker_flags} }, @extra_linker_flags;
      return;
   }

   $self->fail( $diag );
}

=head2 $mb = $cc->new_module_build( %args )

Construct and return a new L<Module::Build> object, preconfigured with the
C<include_dirs>, C<extra_compiler_flags> and C<extra_linker_flags> options
that have been configured on this object, by the above methods.

This is provided as a simple shortcut for the common use case, that a
F<Build.PL> file is using the C<ExtUtils::CChecker> object to detect the
required arguments to pass.

=cut

sub new_module_build
{
   my $self = shift;
   require Module::Build;

   return Module::Build->new(
      include_dirs         => $self->include_dirs,
      extra_compiler_flags => $self->extra_compiler_flags,
      extra_linker_flags   => $self->extra_linker_flags,
      @_,
   );
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 EXAMPLES

=head2 Socket Libraries

Some operating systems provide the BSD sockets API in their primary F<libc>.
Others keep it in a separate library which should be linked against. The
following example demonstrates how this would be handled.

 use Module::Build;
 use ExtUtils::CChecker;

 my $cc = ExtUtils::CChecker->new;

 $cc->find_libs_for(
    diag => "no socket()",
    libs => [ "", "socket nsl" ],
    source => q[
 #include <sys/socket.h>
 int main(int argc, char *argv) {
   int fd = socket(PF_INET, SOCK_STREAM, 0);
   if(fd < 0)
     return 1;
   return 0;
 }
 ] );

 $cc->new_module_build(
    module_name => "Your::Name::Here",
    requires => {
       'IO::Socket' => 0,
    },
    ...
 )->create_build_script;

By using the C<new_module_build> method, the detected C<extra_linker_flags>
value has been automatically passed into the new C<Module::Build> object.

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
