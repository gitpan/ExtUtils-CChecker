#!/usr/bin/perl -w

use strict;
use Test::More tests => 2;
use Test::Exception;

use ExtUtils::CChecker;

my $cc = ExtUtils::CChecker->new;

lives_ok(
   sub { $cc->assert_compile_run( source => "int main(void) { return 0; }", diag => "OK source" ); },
   'Trivial C program'
);

throws_ok(
   sub { $cc->assert_compile_run( source => "int foo bar splot", diag => "broken source" ); },
   qr/^OS unsupported - broken source$/,
   'Broken C program does not compile and run'
);
