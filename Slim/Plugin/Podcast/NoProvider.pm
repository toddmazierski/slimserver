package Slim::Plugin::Podcast::NoProvider;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;

use base qw(Slim::Plugin::Podcast::Provider);

use Date::Parse qw(str2time);
use List::Util qw(min);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use constant DAYS_TO_SECONDS         => 3600 * 24;
use constant MAX_CONCURRENT_REQUESTS => 4;
use constant MAX_FEEDS               => MAX_CONCURRENT_REQUESTS * 10;
use constant XML_CACHE_TTL           => '5m';

my $prefs = preferences('plugin.podcast');
my $log   = logger('plugin.podcast');

sub getFeedsIterator {
	my ( $self, $feeds ) = @_;
	my $index;

	return sub {
		my $feed = $feeds->[ $index++ ];
		return unless $feed;

		my ($image) = grep { $feed->{$_} } qw(scaled_logo_url logo_url);

		return {
			name        => $feed->{title},
			url         => $feed->{url},
			image       => $feed->{$image},
			description => $feed->{description},
			author      => $feed->{author},
		};
	};
}

sub newsHandler {
	my ( $client, $cb, $args, $passthrough ) = @_;

	my @feed_prefs = @{ $prefs->get('feeds') };
	return $cb->(undef) unless scalar @feed_prefs;

	my $success_callback;
	$success_callback = sub {
		my $items = shift;

		$items =
			[ sort { $b->{pubdate_parsed} <=> $a->{pubdate_parsed} } @$items ];

		my $menu    = 0;
		my $item_id = 0;
		foreach my $item (@$items) {
			$item->{item_id} = join( '.', $menu, $item_id++ );
		}

		$cb->(
			{
				items   => $items,
				actions => {
					info => {
						command   => [ 'podcasts', 'items' ],
						variables => [ 'item_id',  'item_id' ],
					},
				}
			}
		);
	};

	_getNewItems( $client, $success_callback );
}

sub getMenuItems {
	my ( $self, $client ) = @_;

	return [
		{
			name => cstring(
				$client, 'PLUGIN_PODCAST_WHATSNEW', $prefs->get('newSince')
			),
			image => Slim::Plugin::Podcast::Plugin->_pluginDataFor('icon'),
			type  => 'link',
			url   => \&newsHandler,
		}
	];
}

sub getName { 'No provider' }

sub _getNewItems {
	my ( $client, $success_callback ) = @_;

	my @feed_prefs = @{ $prefs->get('feeds') };
	@feed_prefs = @feed_prefs[ 0 .. min( scalar @feed_prefs, MAX_FEEDS ) - 1 ];

	my $min_pub_date   = time - ( $prefs->get('newSince') * DAYS_TO_SECONDS );
	my $max_item_count = $prefs->get('maxNew');

	my $items = [];

	my $workers = 0;
	my $enqueue;
	my $dequeue;

	$dequeue = sub {
		$workers--;
		$enqueue->();
	};

	$enqueue = sub {
		return if $workers >= MAX_CONCURRENT_REQUESTS;

		my $feed_pref = pop @feed_prefs;
		if ( !$feed_pref ) {
			$success_callback->($items) if $workers == 0;
			return;
		}

		$workers++;
		my $url = $feed_pref->{value};

		Slim::Networking::SimpleAsyncHTTP->new(
			sub {
				my $parser = 'Slim::Plugin::Podcast::Parser';
				my $http   = shift;
				my $feed   = eval { $parser->parse($http) };

				my $item_count = 0;

				foreach my $item ( @{ $feed->{items} } ) {
					my $pubdate = str2time( $item->{pubdate} ) || 0;
					my $is_new  = $pubdate >= $min_pub_date;
					last unless $is_new;

					$item->{pubdate_parsed} = $pubdate;
					push @$items, $item;

					$item_count++;
					last if $item_count == $max_item_count;
				}

				$dequeue->();
			},
			sub {
				$log->warn( "can't get new episodes for $url: ", $_[1] );

				$dequeue->();
			},
			{
				cache   => 1,
				expires => XML_CACHE_TTL,
				params  => { client => $client, url => $url }
			}
		)->get($url);

		$enqueue->();
	};

	$enqueue->();
}

1;
