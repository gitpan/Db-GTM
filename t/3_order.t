# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 3;
BEGIN { use_ok('GTM') };
$ENV{'GTMCI'}="/usr/local/gtm/xc/calltab.ci" unless $ENV{'GTMCI'};

#########################

my $db = new GTMDB('SPZ');
ok($db,  "Initialize Database Link"); 
is(&test_order($db),"passed", "\$O,CHILDREN,Correct M Collating Order");

system("stty sane"); # gtm_init() screws up the terminal 

sub test_order {
  my($db) = @_;
  $db->set("TEST_ORDER","A","FOO");
  $db->set("TEST_ORDER","1","BAR");
  $db->set("TEST_ORDER","2","BAZ");
  $db->set("TEST_ORDER","100","BOO");
  $db->set("TEST_ORDER","-5","BOOO");
  $db->set("TEST_ORDER","-10","BOOO");
  $db->set("TEST_ORDER","-5.5","BOOOZ");
  $db->set("TEST_ORDER","1.1","BOZO");
  $db->set("TEST_ORDER","ALPHA","BOOOL");
  $db->set("TEST_ORDER","B","BOOLOO");
  # Order should be [ -10 -5.5 -5 1 1.1 2 100 A ALPHA B ]
  my($ch) = join(":",$db->children("TEST_ORDER"));
  if($ch ne "-10:-5.5:-5:1:1.1:2:100:A:ALPHA:B") { return "failed children"; }
  if($db->order("TEST_ORDER","") ne "-10")    { 
    return "failed - null string to 1st"; 
  }
  if($db->order("TEST_ORDER","A") ne "ALPHA") { 
    return "failed - undefined value to defined"; 
  }
  if($db->order("TEST_ORDER",1) ne "1.1")     { 
    return "failed - collating order wrong"; 
  }
  return "passed";
}
