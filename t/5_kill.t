# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 3;
BEGIN { use_ok('GTM') };
$ENV{'GTMCI'}="/usr/local/gtm/xc/calltab.ci" unless $ENV{'GTMCI'};

#########################

my $db = new GTMDB('SPZ');
ok($db,  "Initialize Database Link"); 
is(&test_kill($db), "passed", "Data delete");
system("stty sane"); # gtm_init() screws up the terminal 

sub test_kill {
  my($db) = @_;
  $db->set("TEST_KILL","A","BOO");
  $db->set("TEST_KILL","A",1,"FOO");
  $db->set("TEST_KILL","A",2,"BAR");
  $db->set("TEST_KILL","A",3,"BAZ");
  $db->set("TEST_KILL","B","BOO");
  $db->set("TEST_KILL","B",1,"FOO");
  $db->set("TEST_KILL","B",2,"BAR");
  $db->set("TEST_KILL","B",3,"BAZ");
  $db->set("TEST_KILL","C","BOO");
  $db->set("TEST_KILL","C",1,"FOO");
  $db->set("TEST_KILL","C",2,"BAR");
  $db->set("TEST_KILL","C",3,"BAZ");

  $db->kv("TEST_KILL","A");   # Only 'A' should be dead
  if(defined  $db->get("TEST_KILL","A"))   { return "failed kv"; }
  if(!defined $db->get("TEST_KILL","A",1)) { return "failed kv"; }
  $db->ks("TEST_KILL","B");   # 'B' should be OK, but not subs
  if(!defined $db->get("TEST_KILL","B"))   { return "failed ks"; }
  if(defined  $db->get("TEST_KILL","B",2)) { return "failed ks"; }
  $db->kill("TEST_KILL","C"); # 'C' & subs should be dead
  if(defined  $db->get("TEST_KILL","C"))   { return "failed kill"; }
  if(defined  $db->get("TEST_KILL","C",3)) { return "failed kill"; }
  return "passed";
}
