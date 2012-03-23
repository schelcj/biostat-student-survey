#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use YAML qw(LoadFile);
use Data::Dumper;

my $agent = get_login_agent();

print Dumper $agent;

sub get_login_agent {
  my $cosign = qq($ENV{HOME}/.config/umich/cosign.yml);
  my $yaml   = LoadFile($cosign);
  my $www    = WWW::Mechanize->new();

  $www->get($yaml->{login_url});
  $www->post(qq($yaml->{login_url}/$yaml->{login_cgi}),
    {
      login    => $yaml->{username},
      password => $yaml->{password},
      ref      => 'https://lessons.ummu.umich.edu/2k/manage/workspace/reader',
      service  => 'cosign-lessons.ummu',
    }
  );

  return $www;
}

sub create_survey {
  my ($agent) = @_;

}
