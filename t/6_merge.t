# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 3;
BEGIN { use_ok('GTM') };
$ENV{'GTMCI'}="/usr/local/gtm/xc/calltab.ci" unless $ENV{'GTMCI'};

#########################

my $db = new GTMDB('SPZ');
ok($db,  "Initialize Database Link"); 
is(&test_merge($db),"passed", "Hierarchy Merge");

system("stty sane"); # gtm_init() screws up the terminal 

sub test_merge {
  $db->set("TEST_MERGE","A","FOO");
  $db->set("TEST_MERGE","A",3,"FOO");
  $db->set("TEST_MERGE","A",4,"FOO");
  $db->set("TEST_MERGE","A",5,"FOO");
  $db->set("TEST_MERGE","B",1,"BAR");
  $db->set("TEST_MERGE","B",2,"BAR");
  $db->set("TEST_MERGE","B",3,"BAR");
  $db->copy("TEST_MERGE","A",undef,"TEST_MERGE","B");

  if($db->get("TEST_MERGE","B") ne "FOO")   { return "failed"; }
  if($db->get("TEST_MERGE","B",1) ne "BAR") { return "failed"; }
  if($db->get("TEST_MERGE","B",3) ne "FOO") { return "failed"; }
  if($db->get("TEST_MERGE","B",5) ne "FOO") { return "failed"; }
  return "passed";
}
