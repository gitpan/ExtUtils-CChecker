#!/usr/bin/perl -w

use strict;
use Test::More tests => 5;

use ExtUtils::CChecker;

my $cc = ExtUtils::CChecker->new;

ok( defined $cc, 'defined $cc' );
isa_ok( $cc, "ExtUtils::CChecker", '$cc' );

ok( $cc->try_compile_run( "int main(void) { return 0; }" ), 'Trivial C program compiles and runs' );
ok( !$cc->try_compile_run( "int foo bar splot" ), 'Broken C program does not compile and run' );

ok( $cc->try_compile_run( source => "int main(void) { return 0; }" ), 'source named argument' );
