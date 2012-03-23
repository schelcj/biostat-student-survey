#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use YAML qw(LoadFile);
use Data::Dumper;
use Readonly;

Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};

my $agent    = get_login_agent();
my $students = [
  {
    name     => 'Test User',
    uniqname => 'uniqname',
  },
];

foreach my $student_ref (@{$students}) {
  create_survey($agent, $student_ref);
  say "Created survey for $student_ref->{name}";
}

sub get_login_agent {
  my $cosign = qq($ENV{HOME}/.config/umich/cosign.yml);
  my $yaml   = LoadFile($cosign);
  my $www    = WWW::Mechanize->new();

  $www->get($yaml->{login_url});
  $www->post(
    qq($yaml->{login_url}/$yaml->{login_cgi}), {
      login    => $yaml->{username},
      password => $yaml->{password},
      ref      => qq{$UMLESSONS_URL/2k/manage/workspace/reader},
      service  => 'cosign-lessons.ummu',
    }
  );

  return $www;
}

sub create_survey {
  my ($agent, $student) = @_;

  my $uniqname    = $student->{uniqname};
  my $description = qq(Survey for $student->{name}.);

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/setup/unit_4631}, {
      op    => 'Continue...',
      style => 'survey',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_settings/unit_4631}, {
      charset               => '!',
      firstItemFirst        => 'FALSE',
      howManyItemsDisplayed => 'ALL',
      keywords              => '',
      lastItemLast          => 'FALSE',
      name                  => $uniqname,
      navigationOptions     => 'random-access',
      new_setup             => '1',
      op                    => 'save',
      other_charset         => '',
      presentationStyle     => 'single-page',
      randomization         => 'FALSE',
      repeatOptions         => 'infinite',
      showBanner            => 'TRUE',
      showFooter            => 'TRUE',
      showLinks             => 'TRUE',
      style                 => 'survey',
      title                 => $uniqname,
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/unit_4631\$unit_4631/$uniqname}, {
      directionsText => $description,
      op             => 'save',
      section        => 'directions',
    }
  );

  return $agent;
}
