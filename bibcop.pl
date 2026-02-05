#!/usr/bin/env perl

use strict;
use warnings;

eval q{
    END {
        my $cleaning = 0;
        foreach (@ARGV) { $cleaning = 1 if /^-c|^-C|^-gg/i; }
        
        unless ($cleaning) {
            my $mode = 'bib';
            {
                no strict 'vars';
                if (defined $BibCopMode) { $mode = $BibCopMode; }
                elsif (defined $main::BibCopMode) { $mode = $main::BibCopMode; }
            }
            
            my $custom_rules = undef;
            {
                no strict 'vars';
                if (defined $BibCheckRules) { $custom_rules = $BibCheckRules; }
                elsif (defined $main::BibCheckRules) { $custom_rules = $main::BibCheckRules; }
            }

            if ($mode eq 'bbl') {
                my $rules = defined $custom_rules ? $custom_rules : 'bblrules.conf';
                if (-e $rules) {
                    run_bibcop('bbl', $rules);
                } else {
                    report_fatal_error("Config file '$rules' not found (Mode: bbl). Upload it or check .latexmkrc.");
                }
            } else {
                my $rules = defined $custom_rules ? $custom_rules : 'bibrules.conf';
                if (-e $rules) {
                    run_bibcop('bib', $rules);
                } else {
                    report_fatal_error("Config file '$rules' not found (Mode: bib). Upload it or check .latexmkrc.");
                }
            }
        }
    }
};

sub report_fatal_error {
    my ($msg) = @_;
    my $log_file = find_log_file();
    
    if (defined $log_file && -e $log_file) {
        if (open my $out, '>>', $log_file) {
            print $out "\n\n! Package BibCop Error: $msg\n";
            print $out "(BibCop)                Fatal error. Stopping check.\n\n";
            close $out;
        }
    }
    print "\n! Package BibCop Error: $msg\n";
    die "\n!!! BibCop Fatal Error: $msg !!!\n";
}

sub find_log_file {
    my $log_file;
    my $latest_mtime = 0;
    foreach my $f (glob("*.log")) {
        my $mtime = (stat($f))[9];
        if ($mtime > $latest_mtime) {
            $latest_mtime = $mtime;
            $log_file = $f;
        }
    }
    return $log_file;
}

sub run_bibcop {
    my ($type, $rules_file) = @_; 

    my @rules;
    if (open my $rh, '<', $rules_file) {
        while (<$rh>) {
            next if /^\s*#/ || /^\s*$/;
            chomp;
            my @parts = map { s/^\s+|\s+$//gr } split /\|/;
            push @rules, \@parts if @parts >= 4;
        }
        close $rh;
    } else {
        report_fatal_error("Could not read rule file '$rules_file': $!");
        return;
    }

    my @target_files;
    if ($type eq 'bib') {
        my %used_bibs;
        foreach my $aux (glob("*.aux")) {
            if (open my $afh, '<', $aux) {
                while (<$afh>) {
                    if (/\\bibdata\{(.+?)\}/) {
                        foreach my $b (split /,/, $1) {
                            $b =~ s/^\s+|\s+$//g; $b .= ".bib" unless $b =~ /\.bib$/;
                            $used_bibs{$b} = 1;
                        }
                    }
                }
                close $afh;
            }
        }
        foreach my $bcf (glob("*.bcf")) {
            if (open my $bfh, '<', $bcf) {
                while (<$bfh>) {
                    if (/>([^<]+\.bib)</) { $used_bibs{$1} = 1; }
                }
                close $bfh;
            }
        }
        @target_files = keys %used_bibs;
        if (@target_files == 0) { @target_files = glob("*.bib"); }
    } 
    elsif ($type eq 'bbl') {
        if (-e 'output.bbl') { push @target_files, 'output.bbl'; }
        my @tex_files = glob("*.tex");
        foreach my $tex (@tex_files) {
            my $bbl = $tex;
            $bbl =~ s/\.tex$/.bbl/;
            push @target_files, $bbl if (-e $bbl && $bbl ne 'output.bbl');
        }
        if (@target_files == 0) { @target_files = glob("*.bbl"); }
    }

    return if @target_files == 0;

    my $log_file = find_log_file();
    return unless defined $log_file;

    my @error_msgs;
    my @warn_msgs;
    
    my $prefix = ($type eq 'bbl') ? "BibCop" : "BibCop";

    foreach my $file (@target_files) {
        open my $fh, '<', $file or next;
        my $content = do { local $/; <$fh> };
        close $fh;

        my %entries; 
        if ($type eq 'bib') {
            while ($content =~ /@(\w+)\s*\{\s*([^,]+),(.+?)\n\}/gs) {
                $entries{$2} = { body => $3, pos => $-[0] };
            }
        } elsif ($type eq 'bbl') {
            while ($content =~ /\\bibitem(?:\[.*?\])?\{(.+?)\}(.+?)(?=\\bibitem|\\end\{thebibliography\})/gs) {
                $entries{$1} = { body => $2, pos => $-[0] };
            }
        }

        foreach my $key (sort keys %entries) {
            my $body = $entries{$key}->{body};
            my $line_num = (substr($content, 0, $entries{$key}->{pos}) =~ tr/\n//) + 1;

            foreach my $rule (@rules) {
                my ($field, $op, $pat, $lv, $msg) = @$rule;
                
                next if ($type eq 'bib' && ($field eq 'entry' || $field eq '*'));
                next if ($type eq 'bbl' && $field ne 'entry' && $field ne '*');
                
                my $violation = 0;
                my $val = $body; 

                if ($type eq 'bib') {
                    if ($body =~ /^\s*\Q$field\E\s*=\s*(.+?)\s*,?\s*$/msi) {
                        my $raw = $1; $raw =~ s/^[\s"{]+//; $raw =~ s/[\s"}]+$//;
                        $val = $raw;
                    } else { $val = undef; }
                }

                if ($op eq 'missing') {
                    $violation = 1 unless defined $val;
                } elsif (defined $val) {
                    if ($op eq '~') { $violation = 1 if $val =~ /$pat/; }
                    elsif ($op eq '!~') { $violation = 1 if $val !~ /$pat/; }
                    elsif ($op eq 'contains') { $violation = 1 if index($val, $pat) != -1; }
                }

                if ($violation) {
                    $msg =~ s/^"|"$//g;
                    my $log_msg = ($lv =~ /ERROR/i) ? "\n! Package $prefix Error: [$key] $msg\n" : "\nPackage $prefix Warning: [$key] $msg\n";
                    $log_msg .= "($prefix)                on input line $line_num in file $file.\n";
                    
                    if ($lv =~ /ERROR/i) { push @error_msgs, $log_msg; }
                    else { push @warn_msgs, $log_msg; }
                }
            }
        }
    }

    my $all_messages = join("", @warn_msgs) . join("", @error_msgs);
    if ($all_messages) {
        if (open my $in, '<', $log_file) {
            my $log_content = do { local $/; <$in> };
            close $in;
            my $injection_block = "\n% --- $prefix Results ---$all_messages% ---------------------\n";
            if ($log_content =~ /(Here is how much of)/) {
                $log_content =~ s/(Here is how much of)/$injection_block\n$1/;
            } else { $log_content .= $injection_block; }
            if (open my $out, '>', $log_file) { print $out $log_content; close $out; }
        }
    } else {
        if (open my $out, '>>', $log_file) { print $out "\nPackage $prefix Info: No issues found.\n"; close $out; }
    }
}

1;
