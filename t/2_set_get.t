# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 3;
BEGIN { use_ok('GTM') };
$ENV{'GTMCI'}="/usr/local/gtm/xc/calltab.ci" unless $ENV{'GTMCI'};

#########################

my $db = new GTMDB('SPZ');
ok($db,  "Initialize Database Link"); 
is(&test_set($db),  "passed", "Basic data store/retrieve");

system("stty sane"); # gtm_init() screws up the terminal 

sub test_set {
  my($testval,$db) = ($$,@_);
  $db->set("TEST_SG",41,$testval);
  if($db->get("TEST_SG",41) ne $testval) { return "failed"; }
  else { return "passed"; }
}
