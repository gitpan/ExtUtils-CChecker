use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'ExtUtils::CChecker',
   requires => {
      'ExtUtils::CBuilder' => 0,
   },
   build_requires => {
      'Module::Build' => 0,
      'Test::Exception' => 0,
      'Test::More' => 0,
   },
   license => 'perl',
   create_makefile_pl => 'small',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
