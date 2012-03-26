#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use YAML qw(LoadFile);
use Data::Dumper;
use Readonly;
use Text::Roman;

Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $EMPTY         => q{};
Readonly::Scalar my $BANG          => q{!};

my $agent    = get_login_agent();
my $students = [
  {
    name     => 'Test User',
    uniqname => 'uniqname',
  },
];

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

foreach my $student_ref (@{$students}) {
  say "Creating survey for $student_ref->{name}";
  create_survey($student_ref);
  add_questions();
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
  my ($student) = @_;

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

sub add_questions {
  foreach my $key (sort keys %{$question_ref}) {
    my $type      = $question_ref->{$key}->{type};
    my $question  = $question_ref->{$key}->{question};

    if ($type eq 'multiple_choice') {
      my $responses = $question_ref->{$key}->{responses};
      _create_multi_choice_question($question, $responses);

    } elsif ($type eq 'short_answer') {
      _create_short_answer_question($question);

    }
  }

  return;
}

sub _create_multi_choice_question {
  my ($question, $responses) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/unit_4631/uniqname}, {
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
      qq{$UMLESSONS_URL/2k/manage/multiple_choice/update_content/unit_4631/uniqname\$$id}, {
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
  my ($question) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/unit_4631/uniqname}, {
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
