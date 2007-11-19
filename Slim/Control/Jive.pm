package Slim::Control::Jive;

# SqueezeCenter Copyright (c) 2001-2007 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX;
use Scalar::Util qw(blessed);
use File::Spec::Functions qw(:ALL);
use File::Basename;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Buttons::Information;
use Slim::Buttons::Synchronize;
use Slim::Buttons::AlarmClock;
use Slim::Player::Sync;
use Slim::Player::Client;
use Data::Dump;


=head1 NAME

Slim::Control::Jive

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'player.jive',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

# additional top level menus registered by plugins
my %itemsToDelete      = ();
my @extrasPluginMenu   = ();
my @settingsPluginMenu = ();
my @myMusicPluginMenu  = ();
my @searchPluginMenu   = ();

=head1 METHODS

=head2 init()

=cut
sub init {
	my $class = shift;

	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
        [0, 1, 1, \&menuQuery]);

    Slim::Control::Request::addDispatch(['alarmsettings', '_index', '_quantity'], [1, 1, 1, \&alarmSettingsQuery]);
    Slim::Control::Request::addDispatch(['syncsettings', '_index', '_quantity'], [1, 1, 1, \&syncSettingsQuery]);
    Slim::Control::Request::addDispatch(['repeatsettings', '_index', '_quantity'], [1, 1, 1, \&repeatSettingsQuery]);
    Slim::Control::Request::addDispatch(['shufflesettings', '_index', '_quantity'], [1, 1, 1, \&shuffleSettingsQuery]);
    Slim::Control::Request::addDispatch(['sleepsettings', '_index', '_quantity'], [1, 1, 1, \&sleepSettingsQuery]);
    Slim::Control::Request::addDispatch(['crossfadesettings', '_index', '_quantity'], [1, 1, 1, \&crossfadeSettingsQuery]);
    Slim::Control::Request::addDispatch(['replaygainsettings', '_index', '_quantity'], [1, 1, 1, \&replaygainSettingsQuery]);
    Slim::Control::Request::addDispatch(['jivefavorites', '_index', '_quantity'], [1, 1, 1, \&jiveFavoritesQuery]);

	Slim::Control::Request::addDispatch(['date'],
		[0, 1, 0, \&dateQuery]);
	Slim::Control::Request::addDispatch(['firmwareupgrade'],
		[0, 1, 1, \&firmwareUpgradeQuery]);

	Slim::Control::Request::addDispatch(['jiveapplets'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivewallpapers'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivesounds'], [0, 1, 0, \&downloadQuery]);

	Slim::Web::HTTP::addRawDownload('^jive(applet|wallpaper|sound)/', \&downloadFile, 'binary');
}

=head2 getDisplayName()

Returns name of module

=cut
sub getDisplayName {
	return 'JIVE';
}

######
# CLI QUERIES

# handles the "menu" query
sub menuQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client        = $request->client() || 0;
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');

	my $prefs         = preferences("server");
	my $settingsMenu  = playerSettingsMenu($request, $client, $index, $quantity, $prefs);
	my $myMusicMenu   = myMusicMenu();

	# respin @settingsMenu and @myMusicPlugin menu with delete options
	$settingsMenu  = _removeItemsForDeletion('settings', @$settingsMenu);
	$myMusicMenu   = _removeItemsForDeletion('mymusic' , @$myMusicMenu);
	
	# cobble together default menus plus plugin menus
	my @settingsMenu = ( @$settingsMenu, @settingsPluginMenu);
	my @myMusicMenu  = ( @$myMusicMenu, @myMusicPluginMenu);
	
	# as a convention, make weights => 10 and <= 100; Jive items that want to be below all SS items
	# then just need to have a weight > 100, above SS items < 10
	my @menu = (
		{
			text      => Slim::Utils::Strings::string('MY_MUSIC'),
			count     => scalar(@myMusicMenu),
			offset    => 0,
			weight    => 10,
			window    => { titleStyle => 'mymusic', },
			item_loop => \@myMusicMenu,
		},
		{
			text    => Slim::Utils::Strings::string('RADIO'),
			weight  => 20,
			actions => {
				go => {
					cmd => ['radios'],
					params => {
						menu => 'radio',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		},
		{
			text    => Slim::Utils::Strings::string('MUSIC_SERVICES'),
			weight  => 30,
			actions => {
				go => {
					cmd => ['music_services'],
					params => {
						menu => 'music_services',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		},
		{
			text    => Slim::Utils::Strings::string('FAVORITES'),
			weight  => 40,
			actions => {
				go => {
					cmd => ['favorites', 'items'],
					params => {
						menu     => 'favorites',
						#menu_all => '1',
					},
				},
			},
			window        => {
					titleStyle => 'favorites',
			},
		},
		{
			text    => Slim::Utils::Strings::string('PLAYER_PLUGINS'),
			weight  => 45,
			count     => scalar(@extrasPluginMenu),
			offset    => 0,
			item_loop => \@extrasPluginMenu,
			window        => {
			},
		},
		{
			text    => Slim::Utils::Strings::string('SETTINGS'),
			weight  => 50,
			count     => scalar(@settingsMenu),
			offset    => 0,
			item_loop => \@settingsMenu, 
			window        => {
					titleStyle => 'settings',
			},
		},

	);

	if ( blessed($client) && $client->isPlayer() && $client->canPowerOff() ) {
		push @menu, powerHash($client);
	}

	# remove top level main menu items if specified by a plugin
	my $menuForExport = _removeItemsForDeletion('main', @menu);
	my $numitems = scalar(@$menuForExport);
	$request->addResult("count", $numitems);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@$menuForExport[$start..$end]) {			
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}

	$request->setStatusDone();
}

# allow a plugin to add a menu hash entry to appear at the top level of the player menu
sub registerPluginMenu {
	my $menuHash = shift;
	my $whichMenu = shift || 'extras';

	if (ref $menuHash eq 'HASH' && exists $menuHash->{text}) {
		$log->info("Registering menu $menuHash->{text} to $whichMenu");
		if ($whichMenu eq 'extras') {
			push @extrasPluginMenu, $menuHash;
		} elsif ($whichMenu eq 'mymusic') {
			push @myMusicPluginMenu, $menuHash;
		} elsif ($whichMenu eq 'settings') {
			push @settingsPluginMenu, $menuHash;
		} elsif ($whichMenu eq 'search') {
			push @searchPluginMenu, $menuHash;
		}
	}
}

# allow a plugin to delete a main menu from the Jive menu based on the text of the menu item
sub deleteMenuItem {
	my $menuText = shift;
	my $whichMenu = shift || 'main';
	return unless $menuText;
	$log->warn($menuText . " in " . $whichMenu . " slated for deletion");
	$itemsToDelete{$whichMenu}{$menuText}++;
}

sub _removeItemsForDeletion {
	my $whichMenu = shift;
	my @menu = @_;
	my @purgedMenu = ();
	for my $i (0..$#menu) {
		my $textString = defined($menu[$i]->{text}) ? $menu[$i]->{text} : 'skip';
		last unless (defined($menu[$i]));
		if ($itemsToDelete{$whichMenu}{$textString}) {
			$log->warn("REMOVING " . $textString . " FROM " . $whichMenu);
			# only delete it once, giving the opportunity for a
			# custom menu with the same string key to be registered via a plugin
			$itemsToDelete{$whichMenu}{$textString} = 0;
		} else {
			push @purgedMenu, $menu[$i];
		}
	}
	return \@purgedMenu;
}

sub alarmSettingsQuery {

	my $request = shift;
	my $client = $request->client();

	# alarm clock, display for slim proto players
	# still need to pick up saved playlists as list items
	# need to figure out how to handle 24h vs. 12h clock format

	# array ref with 5 elements, each of which is a hashref
	my $day0 = populateAlarmElements($client, 0);

	my @weekDays;
	for my $day (1..7) {
		# @weekDays becomes an array of arrayrefs of hashrefs, one element per weekday
		push @weekDays, populateAlarmHash($client, $day);
	}

	my %weekDayAlarms = (
		text      => Slim::Utils::Strings::string("ALARM_WEEKDAYS"),
		count     => 7,
		offset    => 0,
		item_loop => \@weekDays,
		window    => { titleStyle => 'settings' },
	);

	# one item_loop to rule them all
	my @menu = ( @$day0, \%weekDayAlarms );

	sliceAndShip($request, $client, \@menu);

}

sub syncSettingsQuery {

	my $request           = shift;
	my $client            = $request->client();
	my $playersToSyncWith = getPlayersToSyncWith($client);

	my @menu = @$playersToSyncWith;

	sliceAndShip($request, $client, \@menu);

}

sub repeatSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $val     = Slim::Player::Playlist::repeat($client);
	my @strings = ('REPEAT_OFF', 'REPEAT_ONE', 'REPEAT_ALL',);
	my @menu;

	push @menu, repeatHash($val, \@strings, 0);
	push @menu, repeatHash($val, \@strings, 1);
	push @menu, repeatHash($val, \@strings, 2);

	sliceAndShip($request, $client, \@menu);
}

sub shuffleSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $val     = Slim::Player::Playlist::shuffle($client);
	my @strings = (
		'SHUFFLE_OFF', 'SHUFFLE_ON_SONGS', 'SHUFFLE_ON_ALBUMS',
	);
	my @menu;

	push @menu, shuffleHash($val, \@strings, 0);
	push @menu, shuffleHash($val, \@strings, 1);
	push @menu, shuffleHash($val, \@strings, 2);

	sliceAndShip($request, $client, \@menu);

}

sub sleepSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $val     = $client->currentSleepTime();
	my @menu;

	if ($val > 0) {
		my $sleepString = sprintf(Slim::Utils::Strings::string('SLEEPING_IN_X_MINUTES'), $val);
		push @menu, { text => $sleepString, style => 'itemNoAction' };
		push @menu, sleepInXHash($val, 0);
	}
	push @menu, sleepInXHash($val, 15);
	push @menu, sleepInXHash($val, 30);
	push @menu, sleepInXHash($val, 45);
	push @menu, sleepInXHash($val, 60);
	push @menu, sleepInXHash($val, 90);

	sliceAndShip($request, $client, \@menu);
}

sub crossfadeSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('transitionType');
	my @strings = (
		'TRANSITION_NONE', 'TRANSITION_CROSSFADE', 
		'TRANSITION_FADE_IN', 'TRANSITION_FADE_OUT', 
		'TRANSITION_FADE_IN_OUT'
	);
	my @menu;

	push @menu, transitionHash($val, $prefs, \@strings, 0);
	push @menu, transitionHash($val, $prefs, \@strings, 1);
	push @menu, transitionHash($val, $prefs, \@strings, 2);
	push @menu, transitionHash($val, $prefs, \@strings, 3);
	push @menu, transitionHash($val, $prefs, \@strings, 4);

	sliceAndShip($request, $client, \@menu);

}

sub replaygainSettingsQuery {
	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('replayGainMode');
	my @strings = (
		'REPLAYGAIN_DISABLED', 'REPLAYGAIN_TRACK_GAIN', 
		'REPLAYGAIN_ALBUM_GAIN', 'REPLAYGAIN_SMART_GAIN'
	);
	my @menu;

	push @menu, replayGainHash($val, $prefs, \@strings, 0);
	push @menu, replayGainHash($val, $prefs, \@strings, 1);
	push @menu, replayGainHash($val, $prefs, \@strings, 2);
	push @menu, replayGainHash($val, $prefs, \@strings, 3);

	sliceAndShip($request, $client, \@menu);
}


sub sliceAndShip {
	my ($request, $client, $menu) = @_;
	my $numitems = scalar(@$menu);
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	$request->addResult("count", $numitems);
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@$menu[$start..$end]) {
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}
	$request->setStatusDone()
}

sub playerSettingsMenu {
	my ($request, $client, $index, $quantity, $prefs) = @_;
 
	$log->debug("Begin Function");
 
	my @menu = ();
	return (\@menu, 0) unless $client;

	# always add repeat
	push @menu, {
		text      => Slim::Utils::Strings::string("REPEAT"),
		actions => {
			go => {
				cmd    => ['repeatsettings'],
				player => 0,
			},
		},
		window    => { titleStyle => 'settings' },
	};

	# always add shuffle
	push @menu, {
		text      => Slim::Utils::Strings::string("SHUFFLE"),
		actions => {
			go => {
				cmd    => ['shufflesettings'],
				player => 0,
			},
		},
		window    => { titleStyle => 'settings' },
	};

	# add alarm only if this is a slimproto player
	if ($client->isPlayer()) {
		push @menu, {
			text      => Slim::Utils::Strings::string("ALARM"),
			actions => {
				go => {
					cmd    => ['alarmsettings'],
					player => 0,
				},
			},
		window    => { titleStyle => 'settings' },
		};
	}

	# sleep setting (always)
	push @menu, {
		text      => Slim::Utils::Strings::string("SLEEP"),
		actions => {
			go => {
				cmd    => ['sleepsettings'],
				player => 0,
			},
		},
		window    => { titleStyle => 'settings' },
	};	

	# synchronization. only if numberOfPlayers > 1
	my $synchablePlayers = howManyPlayersToSyncWith($client);
	if ($synchablePlayers > 0) {
		push @menu, {
			text      => Slim::Utils::Strings::string("SYNCHRONIZE"),
			actions => {
				go => {
					cmd    => ['syncsettings'],
					player => 0,
				},
			},
		window    => { titleStyle => 'settings' },
		};	
	}

	# transition only for Sb2 and beyond
	if ($client->isa('Slim::Player::Squeezebox2')) {
		push @menu, {
			text      => Slim::Utils::Strings::string("SETUP_TRANSITIONTYPE"),
			actions => {
				go => {
					cmd    => ['crossfadesettings'],
					player => 0,
				},
			},
		window    => { titleStyle => 'settings' },
		};	
	}

	# replay gain (volume adjustment)
	if ($client->canDoReplayGain(0)) {
		push @menu, {
			text      => Slim::Utils::Strings::string("REPLAYGAIN"),
			actions   => {
				  go => {
					cmd    => ['replaygainsettings'],
					player => 0,
				  },
			},
		window    => { titleStyle => 'settings' },
		};	
	}

	# player name change, always display
	push @menu, {
		text      => Slim::Utils::Strings::string('INFORMATION_PLAYER_NAME'),
		input => {
			initialText  => $client->name(),
			len          => 1, # For those that want to name their player "X"
			allowedChars => Slim::Utils::Strings::string('JIVE_ALLOWEDCHARS_WITHCAPS'),
			help         => {
				           text => Slim::Utils::Strings::string('JIVE_CHANGEPLAYERNAME_HELP')
			},
			softbutton1  => Slim::Utils::Strings::string('INSERT'),
			softbutton2  => Slim::Utils::Strings::string('DELETE'),
		},
		actions => {
			do => {
				player => 0,
				cmd    => ['name'],
				params => {
					playername => '__INPUT__',
				},
			},
		},
		window    => { titleStyle => 'settings' },
	};

	# information, always display
	my $playerInfoText = sprintf(Slim::Utils::Strings::string('INFORMATION_SPECIFIC_PLAYER'), $client->name());
	push @menu, {
		text      => $playerInfoText,
		offset    => 0,
		count	  => 1,
		window    => { titleStyle => 'settings' },
		textArea => 
			Slim::Utils::Strings::string("INFORMATION_PLAYER_NAME_ABBR") . ": " . 
			$client->name() . "\n\n" . 
			Slim::Utils::Strings::string("INFORMATION_PLAYER_MODEL_ABBR") . ": " .
			Slim::Buttons::Information::playerModel($client) . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_FIRMWARE_ABBR") . ": " . 
			$client->revision() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_IP_ABBR") . ": " .
			$client->ip() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_PORT_ABBR") . ": " .
			$client->port() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_MAC_ABBR") . ": " .
			uc($client->macaddress())
			,
	};

	return \@menu;
}

sub howManyPlayersToSyncWith {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my $synchablePlayers = 0;
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		$synchablePlayers++;
	}
	return $synchablePlayers;
}

sub getPlayersToSyncWith() {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my @return = ();
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		my $val = Slim::Player::Sync::isSyncedWith($client, $player); 
		push @return, { 
			text => $player->name(), 
			checkbox => ($val == 1) + 0,
			actions  => {
				on  => {
					player => 0,
					cmd    => ['sync', $player->id()],
				},
				off => {
					player => $player->id(),
					cmd    => ['sync', '-'],
				},
			},		
		};
	}
	return \@return;
}

sub dateQuery {
	my $request = shift;

	if ( $request->isNotQuery([['date']]) ) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# Calculate the time zone offset, taken from Time::Timezone
	my $time = time();
	my @l    = localtime($time);
	my @g    = gmtime($time);

	my $off 
		= $l[0] - $g[0]
		+ ( $l[1] - $g[1] ) * 60
		+ ( $l[2] - $g[2] ) * 3600;

	# subscript 7 is yday.

	if ( $l[7] == $g[7] ) {
		# done
	}
	elsif ( $l[7] == $g[7] + 1 ) {
		$off += 86400;
	}
	elsif ( $l[7] == $g[7] - 1 ) {
			$off -= 86400;
	} 
	elsif ( $l[7] < $g[7] ) {
		# crossed over a year boundry!
		# localtime is beginning of year, gmt is end
		# therefore local is ahead
		$off += 86400;
	}
	else {
		$off -= 86400;
	}

	my $hour = int($off / 3600);
	if ( $hour > -10 && $hour < 10 ) {
		$hour = "0" . abs($hour);
	}
	else {
		$hour = abs($hour);
	}

	my $tzoff = ( $off >= 0 ) ? '+' : '-';
	$tzoff .= sprintf( "%s:%02d", $hour, int( $off % 3600 / 60 ) );

	# Return time in http://www.w3.org/TR/NOTE-datetime format
	$request->addResult( 'date', strftime("%Y-%m-%dT%H:%M:%S", localtime) . $tzoff );

	$request->setStatusDone();
}

sub firmwareUpgradeQuery {
	my $request = shift;

	if ( $request->isNotQuery([['firmwareupgrade']]) ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $firmwareVersion = $request->getParam('firmwareVersion');
	
	# always send the upgrade url this is also used if the user opts to upgrade
	if ( my $url = Slim::Utils::Firmware->jive_url() ) {
		$request->addResult( firmwareUrl => $url );
	}
	
	if ( Slim::Utils::Firmware->jive_needs_upgrade( $firmwareVersion ) ) {
		# if this is true a firmware upgrade is forced
		$request->addResult( firmwareUpgrade => 1 );
	}
	else {
		$request->addResult( firmwareUpgrade => 0 );
	}
	
	$request->setStatusDone();
}

sub alarmOnHash {
	my ($client, $prefs, $day) = @_;
	my $val = $prefs->client($client)->get('alarm')->[ $day ];
	my %return = (
		text     => Slim::Utils::Strings::string("ENABLED"),
		checkbox => ($val == 1) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => $day,
					enabled => 1,
				},
			},
			off => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => $day,
					enabled => 0,
				},
			},
		},
	);
	return \%return;
}

sub alarmSetHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmtime')->[ $day ];
	my %return = 
	( 
		text    => Slim::Utils::Strings::string("ALARM_SET"),
		input   => {
			initialText  => $current_setting, # this will need to be formatted correctly
			_inputStyle  => 'time',
			len          => 1,
			help         => {
				text => Slim::Utils::Strings::string('JIVE_ALARMSET_HELP')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => ['alarm'],
				params => {
					cmd => 'set',
					dow =>	$day,
					time => '__TAGGEDINPUT__',	
				},
			},
		},
	);
	return \%return;
}

sub alarmPlaylistHash {
	my ($client, $prefs, $day) = @_;
	my $alarm_playlist = $prefs->client($client)->get('alarmplaylist')->[ $day ];
	my @allPlaylists = (
		{
			text    => Slim::Utils::Strings::string("CURRENT_PLAYLIST"),
			radio	=> ($alarm_playlist == -1) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd    => ['alarms'],
					params => {
						playlist_id => '-1',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_TRACK"),
			radio	=> ($alarm_playlist == -2) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd    => ['alarms'],
					params => {
						playlist_id => '-2',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_ALBUM"),
			radio	=> ($alarm_playlist == -3) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd    => ['alarms'],
					params => {
						playlist_id => '-3',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_CONTRIBUTOR"),
			radio	=> ($alarm_playlist == -4) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd    => ['alarms'],
					params => {
						playlist_id => '-4',
						dow         => $day,
					},
				},
			},
		},
	);
	## here we need to figure out how to populate the remaining playlist items from saved playlists
	push @allPlaylists, getCustomPlaylists($client);

	my %return = 
	( 
		text => Slim::Utils::Strings::string("ALARM_SELECT_PLAYLIST"),
		count     => 4,
		offset    => 0,
		item_loop => \@allPlaylists,
	);
	return \%return;
}

sub getCustomPlaylists {
	my @return = ();
	return \@return;
}

sub alarmVolumeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmvolume')->[ $day ];
	my @vol_settings;
	for (my $i = 10; $i <= 100; $i = $i + 10) {
		my %hash = (
			text    => $i,
			radio   => ($i == $current_setting) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd => 'set',
						volume => $i,
						dow => $day,
					},
				},
			},
		);
		push @vol_settings, \%hash;
	}
	my %return = 
	( 
		text      => Slim::Utils::Strings::string("ALARM_SET_VOLUME"),
		count     => 10,
		offset    => 0,
		item_loop => \@vol_settings,
	);
	return \%return;
}

sub alarmFadeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmfadeseconds');
	my %return = 
	( 
		text     => Slim::Utils::Strings::string("ALARM_FADE"),
		checkbox => ($current_setting > 0) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => 0,
					fade    => 1,
				},
			},
			off  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => 0,
					fade    => 0,
				},
			},
		},
	);
	return \%return;
}

sub populateAlarmElements {
	my $client = shift;
	my $day = shift;
	my $prefs = preferences("server");

	my $alarm_on       = alarmOnHash($client, $prefs, $day);
	my $alarm_set      = alarmSetHash($client, $prefs, $day);
	my $alarm_playlist = alarmPlaylistHash($client, $prefs, $day);
	my $alarm_volume   = alarmVolumeHash($client, $prefs, $day);
	my $alarm_fade     = alarmFadeHash($client, $prefs, $day);

	my @return = ( 
		$alarm_on,
		$alarm_set,
		$alarm_playlist,
		$alarm_volume,
	);
	push @return, $alarm_fade if $day == 0;
	return \@return;
}

sub populateAlarmHash {
	my $client = shift;
	my $day = shift;
	my $elements = populateAlarmElements($client, $day);
	my $string = 'ALARM_DAY' . $day;
	my %return = (
		text      => Slim::Utils::Strings::string($string),
		count     => 4,
		offset    => 0,
		item_loop => $elements,
	);
#	Data::Dump::dump(%return);
	return \%return;
}

sub powerHash {
	my $client = shift;
	my $name  = $client->name();
	my $power = $client->power();
	my %return; 
	my ($text, $action);

	if ($power == 1) {
		$text = sprintf(Slim::Utils::Strings::string('JIVE_TURN_PLAYER_OFF'), $name);
		$action = 0;
	} else {
		$text = sprintf(Slim::Utils::Strings::string('JIVE_TURN_PLAYER_ON'), $name);
		$action = 1;
	}

	%return = ( 
		text    => $text,
		weight  => 95,
		actions  => {
			do  => {
				player => 0,
				cmd    => ['power', $action],
			},
		},
	);
	return \%return;
}

sub sleepInXHash {
	my ($val, $sleepTime) = @_;
	my $minutes = Slim::Utils::Strings::string('MINUTES');
	my $text = $sleepTime == 0 ? 
		Slim::Utils::Strings::string("SLEEP_CANCEL") :
		$sleepTime . " " . $minutes;
	my %return = ( 
		text    => $text,
		radio	=> ($val == ($sleepTime*60)) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['sleep', $sleepTime*60 ],
			},
		},
	);
	return \%return;
}

sub repeatHash {
	my ($val, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playlist', 'repeat', "$thisValue" ],
			},
		},
	);
	return \%return;
}

sub shuffleHash {
	my ($val, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd => ['playlist', 'shuffle', "$thisValue"],
				},
			},
	);
	return \%return;
};

sub transitionHash {
	
	my ($val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playerpref', 'transitionType', "$thisValue" ],
			},
		},
	);
	return \%return;
}

sub replayGainHash {
	
	my ($val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
			actions => {
			do => {
				player => 0,
				cmd => ['replayGainMode', "$thisValue"],
			},
		},
	);
	return \%return;
}

sub myMusicMenu {
	my $searchMenu = searchMenu();
	my @return = (
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_ALBUM'),
				weight  => 10,
				actions => {
					go => {
						cmd    => ['albums'],
						params => {
							menu     => 'track',
						},
					},
				},
				window => {
					menuStyle => 'album',
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_ARTIST'),
				weight  => 20,
				actions => {
					go => {
						cmd    => ['artists'],
						params => {
							menu => 'album',
						},
					},
				},
				window => {
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_GENRE'),
				weight  => 30,
				actions => {
					go => {
						cmd    => ['genres'],
						params => {
							menu => 'artist',
						},
					},
				},
				window => {
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_YEAR'),
				weight  => 40,
				actions => {
					go => {
						cmd    => ['years'],
						params => {
							menu => 'album',
						},
					},
				},
				window => {
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_NEW_MUSIC'),
				weight  => 50,
				actions => {
					go => {
						cmd    => ['albums'],
						params => {
							menu => 'track',
							sort => 'new',
						},
					},
				},
				window => {
					menuStyle => 'album',
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_MUSIC_FOLDER'),
				weight  => 70,
				actions => {
					go => {
						cmd    => ['musicfolder'],
						params => {
							menu => 'musicfolder',
						},
					},
				},
				window => {
					titleStyle => 'mymusic',
				},
			},
			{
				text    => Slim::Utils::Strings::string('SAVED_PLAYLISTS'),
				weight  => 80,
				actions => {
					go => {
						cmd    => ['playlists'],
						params => {
							menu => 'track',
						},
					},
				},
				window => {
					titleStyle => 'mymusic',
				},
			},
			{
				text      => Slim::Utils::Strings::string('SEARCH'),
				count     => scalar(@$searchMenu),
				offset    => 0,
				weight    => 90,
				window    => { titleStyle => 'search', },
				item_loop => $searchMenu,
			},
		);
	return \@return;
}

sub searchMenu {
	my @searchMenu = (
	{
		text  => Slim::Utils::Strings::string('ARTISTS'),
		input => {
			len  => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['artists'],
				params => {
					menu     => 'album',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'artists',
				},
			},
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_ARTISTS'),
			titleStyle => 'search',
		},
	},
	{
		text  => Slim::Utils::Strings::string('ALBUMS'),
		input => {
			len => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['albums'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
					_searchType => 'albums',
				},
			},
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_ALBUMS'),
			menuStyle => 'album',
			titleStyle => 'search',
		},
	},
	{
		text  => Slim::Utils::Strings::string('SONGS'),
		input => {
			len => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['tracks'],
				params => {
					menu     => 'track',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'tracks',
				},
			},
		},
		window => {
			'text' => Slim::Utils::Strings::string('SEARCHFOR_SONGS'),
			titleStyle => 'search',
		},
	},
	{
		text  => Slim::Utils::Strings::string('PLAYLISTS'),
		input => {
			len => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['playlists'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
				},
			},
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_PLAYLISTS'),
			titleStyle => 'search',
		},
	},
	);

	# remove any items slated for deletion by a plugin
	my $return  = _removeItemsForDeletion('search', @searchMenu);
	# add any new items from plugins
	@searchMenu = (@$return, @searchPluginMenu);

	return \@searchMenu;

}


# The following allow download of applets, wallpaper and sounds from SC to jive
# Files may be packaged in a plugin or can be added individually via the api below.
#
# In the case of downloads packaged as a plugin, each downloadable file should be 
# available in the 'jive' folder of a plugin and the plugin install.xml file should refer
# to it in the following format:
#
# <jive>
#    <applet>
#       <version>0.1</version>
#       <name>Applet1</name>
#       <file>Applet1.zip</file>
#    </applet>
#    <wallpaper>
#       <name>Wallpaper1</name>
#       <file>Wallpaper1.png</file>
#    </wallpaper>			
#    <wallpaper>
#       <name>Wallpaper2</name>
#       <file>Wallpaper2.png</file>
#    </wallpaper>	
#    <sound>
#       <name>Sound1</name>
#       <file>Sound1.wav</file>
#    </sound>	
# </jive>
#
# Alternatively individual wallpaper and sound files may be registered by the 
# registerDownload and deleteDownload api calls.

# file types allowed for downloading to jive
my %filetypes = (
	applet    => qr/\.zip$/,
	wallpaper => qr/\.(bmp|jpeg|png)$/,
	sound     => qr/\.wav$/,
);

# addditional downloads
my %extras = (
	wallpaper => {},
	sound     => {},
);

=head2 registerDownload()

Register a local file or url for downloading to jive as a wallpaper or sound file.
$type : either 'wallpaper' or 'sound'
$name : description to show on jive
$path : fullpath for file on server or http:// url

=cut

sub registerDownload {
	my $type = shift;
	my $name = shift;
	my $path = shift;

	my $file = basename($path);

	if ($type =~ /wallpaper|sound/ && $file =~ $filetypes{$type} && (-r $path || $path =~ /^http:\/\//)) {

		$log->info("registering download for $type $file $path");

		$extras{$type}->{$file} = {
			'name'    => $name,
			'path'    => $path,
			'file'    => $file,
		};

	} else {
		$log->warn("unable to register download for $type $file");
	}
}

=head2 deleteDownload()

Remove previously registered download entry.
$type : either 'wallpaper' or 'sound'
$path : fullpath for file on server or http:// url

=cut

sub deleteDownload {
	my $type = shift;
	my $path = shift;

	my $file = basename($path);

	if ($type =~ /wallpaper|sound/ && $extras{$type}->{$file}) {

		$log->info("removing download for $type $file");
		delete $extras{$type}->{$file};

	} else {
		$log->warn("unable remove download for $type $file");
	}
}

# downloadable file info from the plugin instal.xml and any registered additions
sub _downloadInfo {
	my $type = shift;

	my $plugins = Slim::Utils::PluginManager::allPlugins();
	my $ret = {};

	for my $key (keys %$plugins) {

		if ($plugins->{$key}->{'jive'} && $plugins->{$key}->{'jive'}->{$type}) {

			my $info = $plugins->{$key}->{'jive'}->{$type};
			my $dir  = $plugins->{$key}->{'basedir'};

			if ($info->{'name'}) {

				my $file = $info->{'file'};

				if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

					if ($ret->{$file}) {
						$log->warn("duplicate filename for download: $file");
					}

					$ret->{$file} = {
						'name'    => $info->{'name'},
						'path'    => catdir($dir, 'jive', $file),
						'file'    => $file,
						'version' => $info->{'version'},
					};

				} else {
					$log->warn("unable to make $key:$file available for download");
				}

			} elsif (ref $info eq 'HASH') {

				for my $name (keys %$info) {

					my $file = $info->{$name}->{'file'};

					if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

						if ($ret->{$file}) {
							$log->warn("duplicate filename for download: $file [$key]");
						}

						$ret->{$file} = {
							'name'    => $name,
							'path'    => catdir($dir, 'jive', $file),
							'file'    => $file,
							'version' => $info->{$name}->{'version'},
						};

					} else {
						$log->warn("unable to make $key:$file available for download");
					}
				}
			}
		}
	}

	# add extra downloads as registered via api
	for my $key (keys %{$extras{$type}}) {
		$ret->{$key} = $extras{$type}->{$key};
	}

	return $ret;
}

sub jiveFavoritesQuery {

	# work-in-progress; not called from anywhere yet
	my $request = shift;
	my $title   = $request->getParam('title');
	my $url     = $request->getParam('url');
	
	$log->warn('BENDEBUG: ' . $title . "|" . $url);
	my $actions = {
		'go' => {
			player => 0,
			cmd    => [ 'favorites', 'add' ],
			params => {
					title => $title,
					url   => 'file://' . $url
			},
		},
	};
	$request->addResult('count', 2);
	$request->addResult('offset', 0);
	$request->addResultLoop('item_loop', 0, 'text', Slim::Utils::Strings::string('JIVE_ADD_TO_FAVORITES'));
	$request->addResultLoop('item_loop', 0, 'actions', $actions);
	$request->addResultLoop('item_loop', 1, 'text', Slim::Utils::Strings::string('CANCEL'));

	$request->setStatusDone();

}


# return all files available for download based on query type
sub downloadQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	my ($type) = $request->getRequest(0) =~ /jive(applet|wallpaper|sound)s/;

	if (!defined $type) {
		$request->setStatusBadDispatch();
		return;
	}

	my $prefs = preferences("server");

	my $cnt = 0;
	my $urlBase = 'http://' . Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport') . "/jive$type/";

	for my $val ( sort { $a->{'name'} cmp $b->{'name'} } values %{_downloadInfo($type)} ) {

		my $url = $val->{'path'} =~ /^http:\/\// ? $val->{'path'} : $urlBase . $val->{'file'};

		my $entry = {
			$type     => $val->{'name'},
			'name'    => Slim::Utils::Strings::getString($val->{'name'}),
			'url'     => $url,
			'file'    => $val->{'file'},
		};

		if ($type eq 'applet') {
			$entry->{'version'} = $val->{'version'};
		}

		$request->setResultLoopHash('item_loop', $cnt++, $entry);
	}	

	$request->addResult("count", $cnt);

	$request->setStatusDone();
}

# convert path to location for download
sub downloadFile {
	my $path = shift;

	my ($type, $file) = $path =~ /^jive(applet|wallpaper|sound)\/(.*)/;

	my $info = _downloadInfo($type);

	if ($info->{$file}) {

		return $info->{$file}->{'path'};

	} else {

		$log->warn("unable to find file: $file for type: $type");
	}
}

1;
