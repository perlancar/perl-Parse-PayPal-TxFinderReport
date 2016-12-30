package Parse::PayPal::TxFinderReport;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any qw($log);

use Exporter qw(import);
our @EXPORT_OK = qw(parse_paypal_txfinder_report);

use DateTime; # XXX use a more lightweight alternative

our %SPEC;

sub _parse_date {
    my $mdy = shift;
    $mdy =~ m!^(\d\d?)/(\d\d?)/(\d\d\d\d)$!
        or die "Invalid date format in '$mdy', must be MM-DD-YYYY";
    DateTime->new(year => $3, month => $1, day => $2)->epoch;
}

$SPEC{parse_paypal_txfinder_report} = {
    v => 1.1,
    summary => 'Parse PayPal transaction detail report into data structure',
    description => <<'_',

The result will be a hashref. The main key is `transactions` which will be an
arrayref of hashrefs.

Dates will be converted into Unix timestamps.

_
    args => {
        file => {
            schema => ['filename*'],
            description => <<'_',

File can be in tab-separated or comma-separated (CSV) format.

_
            pos => 0,
        },
        string => {
            schema => ['str*'],
            description => <<'_',

Instead of `files`, you can alternatively provide the file contents in
`strings`.

_
        },
        format => {
            schema => ['str*', in=>[qw/tsv csv/]],
            description => <<'_',

If unspecified, will be deduced from the filename's extension (/csv/i for
CSV, or /txt|tsv|tab/i for tab-separated).

_
        },
    },
    args_rels => {
        req_one => ['file', 'string'],
    },
};
sub parse_paypal_txfinder_report {
    my %args = @_;

    my $format = $args{format};

    my $handle;
    my $file;
    if (defined(my $str0 = $args{string})) {
        require IO::Scalar;
        require String::BOM;

        if (!$format) {
            $format = $str0 =~ /\t/ ? 'tsv' : 'csv';
        }
        my $str = String::BOM::strip_bom_from_string($str0);
        $handle = IO::Scalar->new(\$str);
        $file = "(string)";
    } elsif (defined(my $file = $args{file})) {
        require File::BOM;

        if (!$format) {
            $format = $file =~ /\.(csv)\z/i ? 'csv' : 'tsv';
        }
        open $handle, "<:encoding(utf8):via(File::BOM)", $file
            or return [500, "Can't open file '$file': $!"];
    } else {
        return [400, "Please specify files (or strings)"];
    }

    my $res = [200, "OK", {
        transactions => [],
    }];

    my $column_names;
    my $code_parse_row = sub {
        my ($row, $rownum) = @_;
        if ($rownum == 1) {
            return [400, "Doesn't find signature in first row"]
                unless @$row && $row->[0] eq 'Search Transactions Results';
        } elsif ($rownum == 2) {
            $column_names = $row;
        } elsif ($rownum >= 4) {
            # skip empty & total row
            return unless @$row;
            return if $row->[0] eq 'Total';

            my $hash = {};
            for (0..@$row) {
                my $key = $column_names->[$_] // "";
                last unless length $key;
                my $v;
                if ($key =~ /^Date$/) {
                    $v = _parse_date($row->[$_]);
                } else {
                    $v = $row->[$_];
                }
                $hash->{$key} = $v;
            }
            push @{ $res->[2]{transactions} }, $hash;
        }
        0;
    };

    if ($format eq 'csv') {
        require Text::CSV;
        my $csv = Text::CSV->new
            or return [500, "Cannot use CSV: ".Text::CSV->error_diag];
        my $rownum = 0;
        while (my $row = $csv->getline($handle)) {
            $rownum++;
            my $row_res = $code_parse_row->($row, $rownum);
            return $row_res if $row_res;
        }
    } else {
        my $rownum = 0;
        while (my $line = <$handle>) {
            $rownum++;
            chomp($line);
            my $row_res = $code_parse_row->([split /\t/, $line], $rownum);
            return $row_res if $row_res;
        }
    }

  RETURN_RES:
    $res;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Parse::PayPal::TxFinderReport qw(parse_paypal_txfinder_report);

 my $res = parse_paypal_txfinder_report(file => );

Sample result when there is a parse error:

 [400, "Doesn't find signature in first row"]

Sample result when parse is successful:

 [200, "OK", {
     format => "txfinder",
     transactions           => [
         {
             "3PL Reference ID"                   => "",
             "Auction Buyer ID"                   => "",
             "Auction Closing Date"               => "",
             "Auction Site"                       => "",
             "Authorization Review Status"        => 1,
             ...
             "Transaction Completion Date"        => 1467273397,
             ...
         },
         ...
     ],
 }]


=head1 DESCRIPTION

PayPal provides various kinds reports which you can retrieve from their website
under Reports menu. This module provides routine to parse PayPal transaction
finder report into a Perl data structure (from the website under Reports >
Transactions > Transaction finder). The CSV format is supported. No official
documentation of the format is available, but it's mostly regular CSV.

Some characteristics of this report:

=over

=item * Date is MM/DD/YYYY only without hour/minute/second information

=item * No transaction status field

=back


=head1 SEE ALSO

L<https://www.paypal.com>

L<Parse::PayPal::TxDetailReport>
