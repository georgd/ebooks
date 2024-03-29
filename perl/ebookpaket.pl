#!/bin/perl 

############################################################
#                                                          #
# ebookpaket.pl - Aufbereitungsskript für EBook-Paket-     #
#                 MARC-Dateien                             #
#                                                          #
# 2018-04-09 Georg Mayr-Duffner                            #
#            georg.mayr-duffner@wu.ac.at                   #
#                                                          #
############################################################

# make it work if running on unix and Catmandu is not installed system wide
# without the need of setting PERL5LIB
if ( exists $ENV{'HOME'} && -d "$ENV{'HOME'}/perl5/lib/perl5" ) {
  use lib "$ENV{'HOME'}/perl5/lib/perl5";
}

use v5.12;
use strict;
use warnings;
use Getopt::Long;
use Catmandu;
use File::Basename;
use File::Spec;
use File::Temp;
use POSIX qw(strftime);
use Log::Any::Adapter;
use Log::Log4perl;
use utf8;
if ($^O =~ m/MSWin32/){
    binmode STDOUT,':encoding(cp850)';
} else {
    binmode STDOUT,':encoding(utf8)';
}

my $type = 'RAW';

GetOptions(#'verbose|v'       => \my $verbose,
           'debug|d'         => \my $debug,
           'input|i=s'       => \my $input,
           'output|o=s'      => \my $output,
           'sigel|s=s'       => \my $sigel,
           'fixfile|fix|f=s' => \my $fixfile,
           'ebasigel|e=s'    => \my $ebasigel,
           'ebadate|x=s'     => \my $ebadate,
           'batch|b'         => \my $isfilter,
           'marc8|m'         => \my $marc8,
           'type|t=s'        => $type,
           'help|hilfe|h|?'  => \my $help,
           ) or usage();

$type = 'XML' if $type =~ m/xml/;

if ($help){usage()};

# OS-independent separator
my $SEP = File::Spec->catfile("","");
my $dir = File::Spec->rel2abs(dirname(__FILE__));
my $datadir = $dir . $SEP . "data";
my $fixdir = $dir . $SEP . ".." . $SEP . "fixes";

my $convfile = undef;

if ($debug){
    Log::Any::Adapter->set('Log4perl');
    Log::Log4perl::init($datadir . $SEP . 'log4perl.conf');

    my $logger = Log::Log4perl->get_logger('myprog');

    $logger->info("Starting main program");
}

if (! $isfilter) {
    # Test for input file
    unless ($input){
        say 'Bitte Eingabedatei angeben:';
        chomp ($input = <STDIN>);
    }
    while (!-e $input){
        say 'Eingabedatei existiert nicht. Bitte neu angeben:';
        chomp ($input = <STDIN>);
    }

    unless ($output){
        say "Bitte Namen für Ausgabedatei angeben und mit <Enter> bestätigen.\n",
            'Wenn die Auswahl leergelassen wird, heißt die Ausgabedatei "output.mrc".';
        chomp ($output = <STDIN>);
        $output = 'output.mrc' unless $output;
    }

    unless ($sigel){
        say 'Bitte ein Paketsigel angeben oder leer lassen und mit <Enter> bestätigen.';
        chomp ($sigel = <STDIN>);
        $sigel = '___' unless $sigel;
    }

    unless ($fixfile){
        say 'Bitte ein Fixfile angeben oder leer lassen für Standardfixfile "ebook.fix".';
        chomp ($fixfile = <STDIN>);
        $fixfile = "${fixdir}${SEP}ebook.fix" unless $fixfile;
       die 'No fix file' unless -e $fixfile;
    }
} else {
    unless($input && $output) {
        print "Fehler: Eingabe- und/oder Ausgabedatei nicht angegeben!\n";
        exit 1;
    }
    unless($sigel) {
        $sigel = '___';
    }
    unless($fixfile) {
        $fixfile = "${fixdir}${SEP}ebook.fix";
    }
}

if ($sigel =~ m/zdb-20-/i) {
    $marc8 = 1;
}

if ($marc8) {
    $convfile = tmpnam();
    say 'Re-encode MARC-8 to UTF-8';
    qx{yaz-marcdump -f MARC-8 -t UTF-8 -o marc -l 9=97 $input > $convfile};
    $input = $convfile;
}

my $today = strftime "%y%m%d", localtime;

my $fixer = Catmandu::Fix->new(
    variables => { ISO2MARC => "${datadir}${SEP}iso3166H2marc.csv",
                   MARC2ISO => "${datadir}${SEP}marc2iso3166H.csv",
                   sigel    => uc($sigel),
                   today    => $today,
                   ebasigel => $ebasigel,
                   ebadate  => $ebadate,
                 },
    fixes => [$fixfile],
);

my $importer = Catmandu->importer('MARC', file => $input, type => $type);
my $exporter = Catmandu->exporter('MARC', file => $output);
my $fixed_importer = $fixer->fix($importer);

$exporter->add_many($fixed_importer->benchmark);
$exporter->commit;

undef($exporter);

if ($convfile && -e "$convfile") {
    unlink "$convfile";
}

sub usage {
    print STDERR << "EOF";

Dieses Programm dient zur Aufbereitung von Ebook-Metadaten.

Verwendung:

$0 --input <Dateipfad> [--output <Dateipfad> --sigel <sigel> --verbose --debug --help]

    --input     -i          Pfad zur Eingabedatei
    --output    -o          Pfad/Dateiname für die Ausgabedatei
    --sigel     -s          Ein spezifisches Paketsigel (optional - wird, wenn
                            möglich vom Fix-File eingetragen. Nötig bei Nomos!
    --ebasigel  -e          Produktsigel für EBA-Paket
    --ebadate   -x          Datum des Upatepakets

EOF
    exit;
}

