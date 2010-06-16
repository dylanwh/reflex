#!/usr/bin/env perl

# This test attaches an event emitter to its watcher at the time the
# emitter is created.  This is more concise than discrete observe()
# calls, and it can be combined with observe() to support multiple
# event consumers per emitter.
#
# Moose provides opportunities for more concise APIs, as we'll see.

use warnings;
use strict;
use lib qw(../lib);

use Reflex::Timer;
use Reflex::Callbacks qw(cb_coderef);

use Test::More tests => 5;

### Create a timer with callbacks.
#
# We don't need a discrete observer since we're not explicitly calling
# observe() on anything.

my $countdown = 3;
my $timer;
$timer = Reflex::Timer->new(
	interval    => 0.1,
	auto_repeat => 1,
	on_tick     => cb_coderef(
		sub {
			pass("'tick' callback invoked ($countdown)");
			$timer = undef unless --$countdown;
		}
	),
);
ok( (defined $timer), "started timer object" );

### Allow the timer and its watcher to run until they are done.

Reflex::Object->run_all();
pass("run_all() returned");

exit;