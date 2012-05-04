#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use YAML qw(LoadFile);
use Data::Dumper;
use Readonly;
use Text::Roman;
use File::Slurp qw(read_file);
use Class::CSV;
use Class::Date;
use Text::Autoformat;

Readonly::Scalar my $EMPTY               => q{};
Readonly::Scalar my $BANG                => q{!};
Readonly::Scalar my $COMMA               => q{,};
Readonly::Scalar my $UMLESSONS_URL       => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $STUDENT_LIST        => $ARGV[0];
Readonly::Scalar my $PUBLISH_DATE_FORMAT => q{%x %I:%S %p};
Readonly::Scalar my $SUMMARY             => q{This survey is part of the Annual Student Evaluation in the Department of Biostatistics, School of Public Health. Please choose the options that best describe your student's academic performance and performance as a GSI and/or GSRA. Please provide some written comments on each student in the boxes provided, if applicable. These comments will be used to prepare the evaluation letter sent to each student.};

Readonly::Array my @STUDENT_HEADERS => (qw(name empl_id uniqname advisor));

## no tidy
my $question_ref = {
  q1 => {
    type      => 'multiple_choice',
    question  => q{How would you rate this students academic year?},
    responses => [qw(Outstanding Excellent Very_Good Good Satisfactory Unsatisfactory Not_able_to_judge)],
  },
  q2 => {
    type      => 'short_answer',
    question  => q{Please comment on the academic performance:},
  },
  q3 => {
    type      => 'multiple_choice',
    question  => q{How would you rate this student as a GSRA?},
    responses => [qw(Outstanding Excellent Very_Good Good Satisfactory Unsatisfactory Not_able_to_judge)],
  },
  q4 => {
    type      => 'short_answer',
    question  => q{Please comment on the GSRA work, if applicable.},
  },
  q5 => {
    type      => 'multiple_choice',
    question  => q{How would you rate this student as a GSI?},
    responses => [qw(Outstanding Excellent Very_Good Good Satisfactory Unsatisfactory Not_able_to_judge)],
  },
  q6 => {
    type      => 'short_answer',
    question  => q{Please comment on the GSI work, if applicable.}
  },
};
## end no tidy

my @students = get_students();
my $agent    = get_login_agent();

foreach my $student_ref (@students) {
  my $full_name = autoformat qq($student_ref->{first_name} $student_ref->{last_name}), { case => 'title' };
  $full_name =~ s/[\r\n]+//g;

  say "Deleting if a survey already exists for $full_name ( $student_ref->{uniqname} )";
  delete_survey($student_ref->{uniqname});

  say "Creating survey for $full_name ( $student_ref->{uniqname} )";
  create_survey($student_ref->{uniqname}, $full_name);

  say "\tAdding questions to survey";
  add_questions($student_ref->{uniqname});

  say "\tPublishing survey";
  publish_survey($student_ref->{uniqname});
}

sub get_students {
  my @list   = ();
  my $csv    = Class::CSV->parse(
    filename => $STUDENT_LIST,
    fields   => \@STUDENT_HEADERS,
  );

  foreach my $line (@{$csv->lines()}) {
    my %student =  map { $_ => lc($line->$_) } @STUDENT_HEADERS;
    ($student{last_name}, $student{first_name}) = split(/$COMMA/, $student{name});
    push @list, \%student;
  }

  return @list;
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

sub delete_survey {
  my ($uniqname) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/tools/x/unit_4631/$uniqname}, {
      op => 'save',
    }
  );

  return;
}

sub create_survey {
  my ($uniqname,$name) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/setup/unit_4631}, {
      op    => 'Continue...',
      style => 'survey',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_settings/unit_4631}, {
      charset               => $BANG,
      firstItemFirst        => 'FALSE',
      howManyItemsDisplayed => 'ALL',
      keywords              => $EMPTY,
      lastItemLast          => 'FALSE',
      name                  => $uniqname,
      navigationOptions     => 'random-access',
      new_setup             => '1',
      op                    => 'save',
      other_charset         => $EMPTY,
      presentationStyle     => 'single-page',
      randomization         => 'FALSE',
      repeatOptions         => 'infinite',
      showBanner            => 'TRUE',
      showFooter            => 'TRUE',
      showLinks             => 'TRUE',
      style                 => 'survey',
      title                 => $name,
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/unit_4631\$unit_4631/$uniqname}, {
      directionsText => $SUMMARY,
      op             => 'save',
      section        => 'directions',
    }
  );

  return;
}

sub publish_survey {
  my ($uniqname) = @_;

  my $now = Class::Date->now();

  $agent->post(
    qq($UMLESSONS_URL/2k/manage/lesson/publish/unit_4631/$uniqname), {
      op            => 'save',
      whenAvailable => 'scheduled',
      WhenCanReview => 'FALSE',
      WhenDue       => undef,
      WhenOpen      => $now->strftime($PUBLISH_DATE_FORMAT),
    }
  );

  return;
}

sub add_questions {
  my ($uniqname) = @_;

  foreach my $key (sort keys %{$question_ref}) {
    my $type      = $question_ref->{$key}->{type};
    my $question  = $question_ref->{$key}->{question};

    if ($type eq 'multiple_choice') {
      my $responses = $question_ref->{$key}->{responses};
      _create_multi_choice_question($uniqname, $question, $responses);

    } elsif ($type eq 'short_answer') {
      _create_short_answer_question($uniqname, $question);

    }
  }

  return;
}

sub _create_multi_choice_question {
  my ($uniqname, $question, $responses) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/unit_4631/$uniqname}, {
      question                             => $question,
      choice                               => 'multiple_choice',
      op                                   => 'Save',
      'multiple_choice:numberAnswers'      => scalar @{$responses},
      'multiple_response:numberAnswers'    => 4,
      'rating_scales:numberAnswers'        => 1,
      'opinion_poll:numberAnswers'         => 5,
      'rating_scale_queries:numberAnswers' => 5,
    }
  );

  my $id = $EMPTY;
  if ($agent->response->base->path =~ m/\$([\w]+)$/g) {
    $id = $1;
  }

  for my $i (0..$#{$responses}) {
    (my $resp    = $responses->[$i]) =~ s/_/ /g;
    my $resp_pos = $i + 1;
    my $roman    = lc(roman($resp_pos));
    my $order    = qq{c$roman.$resp_pos};

    $agent->post(
      qq{$UMLESSONS_URL/2k/manage/multiple_choice/update_content/unit_4631/$uniqname\$$id}, {
        op               => 'save',
        order            => $order,
        qq{order.$order} => $order,
        response         => $resp,
        section          => qq{answers.c$roman},
      }
    );
  }

  return;
}

sub _create_short_answer_question {
  my ($uniqname, $question) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/unit_4631/$uniqname}, {
      op                                   => 'Save',
      question                             => $question,
      choice                               => 'short_answer',
      'multiple_choice:numberAnswers'      => 7,
      'multiple_response:numberAnswers'    => 4,
      'rating_scales:numberAnswers'        => 1,
      'opinion_poll:numberAnswers'         => 5,
      'rating_scale_queries:numberAnswers' => 5,
    }
  );

  return;
}
