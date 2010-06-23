#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package ExtUtils::CChecker;

use strict;
use warnings;

our $VERSION = '0.04';

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

sub define
{
   my $self = shift;
   my ( $symbol ) = @_;

   push @{ $self->{extra_compiler_flags} }, "-D$symbol";
}

=head2 $success = $cc->try_compile_run( %args )

=head2 $success = $cc->try_compile_run( $source )

Try to compile, link, and execute a C program whose source is given. Returns
true if the program compiled and linked, and exited successfully. Returns
false if any of these steps fail.

Takes the following named arguments. If a single argument is given, that is
taken as the source string.

=over 8

=item * source => STRING

The source code of the C program to try compiling, building, and running.

=item * extra_compiler_flags => ARRAY

Optional. If specified, pass extra flags to the compiler.

=item * extra_linker_flags => ARRAY

Optional. If specified, pass extra flags to the linker.

=item * define => STRING

Optional. If specified, then the named symbol will be defined on the C
compiler commandline if the program ran successfully (by passing an option
C<-DI<SYMBOL>>).

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

   $self->define( $args{define} ) if defined $args{define};

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

=head2 $success = $cc->try_find_include_dirs_for( %args )

Try to compile, link and execute the given source, using extra include
directories.

When a usable combination is found, the directories required are stored in the
object for use in further compile operations, or returned by C<include_dirs>.
The method then returns true.

If no a usable combination is found, it returns false.

Takes the following arguments:

=over 8

=item * source => STRING

Source code to compile

=item * dirs => ARRAY of ARRAYs

Gives a list of sets of dirs. Each set of dirs should be strings in its own
array reference.

=item * define => STRING

Optional. If specified, then the named symbol will be defined on the C
compiler commandline if the program ran successfully (by passing an option
C<-DI<SYMBOL>>).

=back

=cut

sub try_find_include_dirs_for
{
   my $self = shift;
   my %args = @_;

   ref( my $dirs = $args{dirs} ) eq "ARRAY" or croak "Expected 'dirs' as ARRAY ref";

   foreach my $d ( @$dirs ) {
      ref $d eq "ARRAY" or croak "Expected 'dirs' element as ARRAY ref";

      $self->try_compile_run( %args, include_dirs => $d ) or next;

      push @{ $self->{include_dirs} }, @$d;

      return 1;
   }

   return 0;
}

=head2 $success = $cc->try_find_libs_for( %args )

Try to compile, link and execute the given source, when linked against a
given set of extra libraries.

When a usable combination is found, the libraries required are stored in the
object for use in further link operations, or returned by
C<extra_linker_flags>. The method then returns true.

If no usable combination is found, it returns false.

Takes the following arguments:

=over 8

=item * source => STRING

Source code to compile

=item * libs => ARRAY of STRINGs

Gives a list of sets of libraries. Each set of libraries should be
space-separated.

=item * define => STRING

Optional. If specified, then the named symbol will be defined on the C
compiler commandline if the program ran successfully (by passing an option
C<-DI<SYMBOL>>).

=back

=cut

sub try_find_libs_for
{
   my $self = shift;
   my %args = @_;

   ref( my $libs = $args{libs} ) eq "ARRAY" or croak "Expected 'libs' as ARRAY ref";

   foreach my $l ( @$libs ) {
      my @extra_linker_flags = map { "-l$_" } split m/\s+/, $l;

      $self->try_compile_run( %args, extra_linker_flags => \@extra_linker_flags ) or next;

      push @{ $self->{extra_linker_flags} }, @extra_linker_flags;

      return 1;
   }

   return 0;
}

=head2 $cc->find_include_dirs_for( %args )

=head2 $cc->find_libs_for( %args )

Calls C<try_find_include_dirs_for> or C<try_find_libs_for> respectively. If it
fails, die with an C<OS unsupported> message.

Each method takes one extra optional argument:

=over 8

=item * diag => STRING

If present, this string will be appended to the failure message if one is
generated. It may provide more useful information to the user on why the OS is
unsupported.

=back

=cut

foreach ( qw( find_libs_for find_include_dirs_for ) ) {
   my $trymethod = "try_$_";

   my $code = sub {
      my $self = shift;
      my %args = @_;

      my $diag = delete $args{diag};
      $self->$trymethod( %args ) or $self->fail( $diag );
   };

   no strict 'refs';
   *$_ = $code;
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

=head2 Testing For Optional Features

Sometimes a function or ability may be optionally provided by the OS, or you
may wish your module to be useable when only partial support is provided,
without requiring it all to be present. In these cases it is traditional to
detect the presence of this optional feature in the F<Build.PL> script, and
define a symbol to declare this fact if it is found. The XS code can then use
this symbol to select between differing implementations. For example, the
F<Build.PL>:

 use Module::Build;
 use ExtUtils::CChecker;

 my $cc = ExtUtils::CChecker->new;

 $cc->try_compile_run(
    define => "HAVE_MANGO",
    source => <<'EOF' );
 #include <mango.h>
 #include <unistd.h>
 int main(void) {
   if(mango() != 0)
     exit(1);
   exit(0);
 }
 EOF

 $cc->new_module_build(
    ...
 )->create_build_script;

If the C code compiles and runs successfully, and exits with a true status,
the symbol C<HAVE_MANGO> will be defined on the compiler commandline. This
allows the XS code to detect it, for example

 int
 mango()
   CODE:
 #ifdef HAVE_MANGO
     RETVAL = mango();
 #else
     croak("mango() not implemented");
 #endif
   OUTPUT:
     RETVAL

This module will then still compile even if the operating system lacks this
particular function. Trying to invoke the function at runtime will simply
throw an exception.

=head2 Linux Kernel Headers

Operating systems built on top of the F<Linux> kernel often share a looser
association with their kernel version than most other operating systems. It
may be the case that the running kernel is newer, containing more features,
than the distribution's F<libc> headers would believe. In such circumstances
it can be difficult to make use of new socket options, C<ioctl()>s, etc..
without having the constants that define them and their parameter structures,
because the relevant header files are not visible to the compiler. In this
case, there may be little choice but to pull in some of the kernel header
files, which will provide the required constants and structures.

The Linux kernel headers can be found using the F</lib/modules> directory. A
fragment in F<Build.PL> like the following, may be appropriate.

 chomp( my $uname_r = `uname -r` );

 my @dirs = (
    [],
    [ "/lib/modules/$uname_r/source/include" ],
 );

 $cc->find_include_dirs_for(
    diag => "no PF_MOONLASER",
    dirs => \@dirs,
    source => <<'EOF' );
 #include <sys/socket.h>
 #include <moon/laser.h>
 int family = PF_MOONLASER;
 struct laserwl lwl;
 int main(int argc, char *argv[]) {
   return 0;
 }
 EOF

This fragment will first try to compile the program as it stands, hoping that
the F<libc> headers will be sufficient. If it fails, it will then try
including the kernel headers, which should make the constant and structure
visible, allowing the program to compile.

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
