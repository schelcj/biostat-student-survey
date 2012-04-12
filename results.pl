#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use WWW::Mechanize::Plugin::FollowMetaRedirect;
use YAML qw(LoadFile);
use Class::CSV;
use Data::Dumper;
use Readonly;
use File::Slurp qw(write_file);
use File::Temp;

Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $EXPORT_URL    => qq{$UMLESSONS_URL/2k/manage/lesson/reports/stats_dataCSV/unit_4631/%s?op=data&mode=response&report_archives=no&sequence=n/a&delim=comma};
Readonly::Scalar my $STUDENT_LIST  => qq($ENV{HOME}/tmp/11_12_students.csv);
Readonly::Scalar my $SUMMARY       => q{studnet_survey_summary.csv};

Readonly::Array my @EXPORT_HEADERS  => (qw(number setup submitted umid uniqname respondent duration q1 q2 q3 q4 q5 q6));
Readonly::Array my @STUDENT_HEADERS => (qw(emplid first_name last_name advisor coadvisor assiting_fall assiting_winter uniqname));

my $summary  = Class::CSV->new(fields => \@EXPORT_HEADERS);
my $agent    = get_login_agent();
my @students = get_students();

foreach my $student_ref (@students) {
  my $file    = File::Temp->new();
  my $results = get_results($student_ref->{uniqname});

  write_file($file->filename, $results);
  add_to_summary($file->filename);
}

write_file($SUMMARY, $summary->string());

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

sub get_students {
  my @list   = ();
  my $csv    = Class::CSV->parse(
    filename => $STUDENT_LIST,
    fields   => \@STUDENT_HEADERS,
  );

  foreach my $line (@{$csv->lines()}) {
    my %student =  map { $_ => lc($line->$_) } @STUDENT_HEADERS;
    push @list, \%student;
  }

  return @list;
}

sub get_results {
  my ($uniqname) = @_;
  my $url        = sprintf $EXPORT_URL, $uniqname;

  $agent->get($url);
  $agent->follow_meta_redirect();

  return $agent->content();
}

sub add_to_summary {
  my ($file) = @_;
  my $csv    = Class::CSV->parse(
                 filename => $file,
                 fields   => \@EXPORT_HEADERS,
               );

  my $line = $csv->lines()->[1];

  if ($line) {
    my $result = {map {$_ => $line->$_} @EXPORT_HEADERS};
    $summary->add_line($result);
  }

  return;
}
