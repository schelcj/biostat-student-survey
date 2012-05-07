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
use Try::Tiny;

Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $EXPORT_URL    => qq{$UMLESSONS_URL/2k/manage/lesson/reports/stats_dataCSV/unit_4631/%s?op=data&mode=response&report_archives=no&sequence=n/a&delim=comma};
Readonly::Scalar my $STUDENT_LIST  => $ARGV[0];
Readonly::Scalar my $SUMMARY       => q{studnet_survey_summary.csv};

Readonly::Array my @EXPORT_HEADERS  => (qw(student number setup submitted umid uniqname respondent duration q1 q2 q3 q4 q5 q6));
Readonly::Array my @STUDENT_HEADERS => (qw(name empl_id uniqname advisor));

my $summary  = Class::CSV->new(fields => \@EXPORT_HEADERS);
my $agent    = get_login_agent();
my @students = get_students();

$summary->add_line({map {$_ => $_} @EXPORT_HEADERS});

foreach my $student_ref (@students) {
  my $file = File::Temp->new(UNLINK => 1, DIR => '/dev/shm', SUFFIX => '.csv', );
  my $results = get_results($student_ref->{uniqname});

  write_file($file->filename, $results);

  try {
    add_to_summary($file->filename, $student_ref->{uniqname});
    say "Added results for $student_ref->{uniqname}";
  } catch {
    say "Failed to parse results for $student_ref->{uniqname}";
  };
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
  my @list = ();
  my $csv  = Class::CSV->parse(
    filename => $STUDENT_LIST,
    fields   => \@STUDENT_HEADERS,
  );

  foreach my $line (@{$csv->lines()}) {
    my %student = map {$_ => lc($line->$_)} @STUDENT_HEADERS;
    push @list, \%student;
  }

  return @list;
}

sub get_results {
  my ($uniqname) = @_;
  my $url = sprintf $EXPORT_URL, $uniqname;

  $agent->get($url);
  $agent->follow_meta_redirect();

  return $agent->content();
}

sub add_to_summary {
  my ($file, $uniqname) = @_;

  my @headers = @EXPORT_HEADERS;
  shift @headers;

  my $csv   = Class::CSV->parse(filename => $file, fields => \@headers);
  my @lines = @{$csv->lines()};

  shift @lines;
  foreach my $line (@lines) {
    my $result         = {map {$_ => $line->$_} @headers};
    $result->{student} = $uniqname;
    
    $summary->add_line($result);
  }

  return;
}
