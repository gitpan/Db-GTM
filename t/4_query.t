# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 3;
BEGIN { use_ok('GTM') };
$ENV{'GTMCI'}="/usr/local/gtm/xc/calltab.ci" unless $ENV{'GTMCI'};

#########################

my $db = new GTMDB('SPZ');
ok($db,  "Initialize Database Link"); 
is(&test_query($db) ,"passed", "\$Query");

system("stty sane"); # gtm_init() screws up the terminal 

sub test_query {
  my($db,$gv) = @_;
  $db->set("TEST_QUERY","A","FOO");
  $db->set("TEST_QUERY","A","B","C","FOO");
  $db->set("TEST_QUERY","A",5,"C","FOO");
  $gv = join(":",$db->query("TEST_QUERY","A"));
  if($gv ne "TEST_QUERY:A:5:C") { return "failed - valid to deeper valid"; }
  $gv = join(":",$db->query("TEST_QUERY","A",5,"C"));
  if($gv ne "TEST_QUERY:A:B:C") { return "failed - valid to higher nested";}
  $gv = join(":",$db->query("TEST_QUERY","A",1000));
  if($gv ne "TEST_QUERY:A:B:C") { return "failed - invalid to valid"; }
  return "passed";
}
