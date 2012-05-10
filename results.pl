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

Readonly::Array my @EXPORT_HEADERS  => (qw(student empl_id number setup submitted umid uniqname respondent duration q1 q2 q3 q4 q5 q6));
Readonly::Array my @STUDENT_HEADERS => (qw(name empl_id uniqname advisor));

my $summary  = Class::CSV->new(fields => \@EXPORT_HEADERS);
my @students = get_students();

$summary->add_line({map {$_ => $_} @EXPORT_HEADERS});

foreach my $student_ref (@students) {
  my $export = get_export($student_ref->{uniqname});

  try {
    add_to_summary($export, $student_ref->{uniqname}, $student_ref->{empl_id});
  } catch {
    say "Failed to parse results for $student_ref->{uniqname}";
    unlink $export;
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
    push @list, {map {$_ => lc($line->$_)} @STUDENT_HEADERS};
  }

  return @list;
}

sub get_export {
  my ($uniqname) = @_;

  my $path = qq(/dev/shm/$uniqname.csv);
  return $path if -e $path;

  write_file($path, get_results($uniqname));

  return $path;
}

sub get_results {
  my ($uniqname) = @_;

  my $agent = get_login_agent();
  $agent->get(sprintf($EXPORT_URL, $uniqname));
  $agent->follow_meta_redirect(ignore_wait => 1);

  return $agent->content();
}

sub add_to_summary {
  my ($file, $uniqname, $empl_id) = @_;

  my @headers = @EXPORT_HEADERS;
  splice(@headers, 0, 2);

  my $csv = Class::CSV->parse(filename => $file, fields => \@headers);
  splice(@{$csv->lines()}, 0, 1);

  foreach my $line (@{$csv->lines()}) {
    my $result = {map {$_ => $line->$_} @headers};
    $result->{student} = $uniqname;
    $result->{empl_id} = qq{'$empl_id};

    $summary->add_line($result);
  }

  return;
}
