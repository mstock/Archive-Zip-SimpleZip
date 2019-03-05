

BEGIN {
    if ($ENV{PERL_CORE}) {
	chdir 't' if -d 't';
	@INC = ("../lib", "lib/compress");
    }
}

use lib qw(lib t t/compress);
use strict;
use warnings;

use Test::More ; 
use CompTestUtils;
use File::Spec ;
use Devel::Peek;

use Carp;
# $SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {    
    # use Test::NoWarnings, if available
    my $extra = 0 ;
    $extra = 1
        if eval { require Test::NoWarnings ;  import Test::NoWarnings; 1 };

    plan tests => 5772 + $extra ;

    use_ok('IO::Uncompress::Unzip', qw(unzip $UnzipError)) ;
    use_ok('IO::Compress::Zip', qw(zip $ZipError)) ;
    use_ok('Archive::Zip::SimpleZip', qw($SimpleZipError ZIP_CM_DEFLATE ZIP_CM_BZIP2 ZIP_CM_STORE)) ;    
    use_ok('Archive::Zip::SimpleUnzip', qw($SimpleUnzipError)) ;
    
    # eval { require Encode ;  import Encode }
    #use_ok('Encode');
}

my $symlink_exists = eval { symlink("", ""); 1 } ;

sub getContent
{
    my $filename = shift;

    my $u = new IO::Uncompress::Unzip $filename, Append => 1, @_
        or die "Cannot open $filename: $SimpleUnzipError";

    isa_ok $u, "IO::Uncompress::Unzip";

    my @content;
    my $status ;

    for ($status = 1; $status > 0 ; $status = $u->nextStream())
    {
        die "xxx" if ! defined $u;
        my %info = %{ $u->getHeaderInfo() } ;
        my $name = $u->getHeaderInfo()->{Name};
        #warn "Processing member $name\n" ;

        my $buff = '';
        1 while ($status = $u->read($buff)) ;
        $info{Payload} = $buff;

        #push @content, [$name, $buff];
        push @content, \%info;
        last unless $status == 0;
    }

    die "Error processing $filename: $status $!\n"
        if $status < 0 ;    

    return @content;
}

sub createZip
{
    my $filename = shift;
    my @data = @{ shift @_ };
    # my %extra = %{ shift @_ // {} };
    my %extra = @_ ? %{ shift @_ } : {} ;
    
    my $z = new Archive::Zip::SimpleZip $filename, %extra ;
    isa_ok $z, "Archive::Zip::SimpleZip";
    
    for my $x (@data)
    {     
        my ($name, $payload, $opts) = @$x;
        #diag "add [$name][$payload]"; 
        ok $z->addString($payload, Name => $name, @$opts), "Added $name" ;
    }
    ok $z->close(), "closed";

    my $entries = scalar @data;
    my @got = getContent($filename);
    is @got, $entries, "$entries entry in zip";
    for (0 .. $entries-1)
    {
        is $got[$_]{Name}, canonFile($data[$_][0]), "Name ok";
        is $got[$_]{Payload}, $data[$_][1], "Payload ok";
    }    
}

sub canonFile
{
    IO::Compress::Zip::canonicalName($_[0], 0);
}

sub canonDir
{
    IO::Compress::Zip::canonicalName($_[0], 1);
}

sub unixToDosTime    # Archive::Zip::Member
{
    my $time_t = shift;
    
    # TODO - add something to cope with unix time < 1980 
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($time_t);
    my $dt = 0;
    $dt += ( $sec >> 1 );
    $dt += ( $min << 5 );
    $dt += ( $hour << 11 );
    $dt += ( $mday << 16 );
    $dt += ( ( $mon + 1 ) << 21 );
    $dt += ( ( $year - 80 ) << 25 );
    return $dt;
}

sub dosToUnixTime
{
    my $dt = shift;

    my $year = ( ( $dt >> 25 ) & 0x7f ) + 80;
    my $mon  = ( ( $dt >> 21 ) & 0x0f ) - 1;
    my $mday = ( ( $dt >> 16 ) & 0x1f );

    my $hour = ( ( $dt >> 11 ) & 0x1f );
    my $min  = ( ( $dt >> 5 ) & 0x3f );
    my $sec  = ( ( $dt << 1 ) & 0x3e );


    use POSIX 'mktime';

    my $time_t = mktime( $sec, $min, $hour, $mday, $mon, $year, 0, 0, -1 );
    return 0 if ! defined $time_t;
    return $time_t;
}

sub roundTripUnixTime
{
    my $t = shift;
    return unixToDosTime(dosToUnixTime($t));
}

if(1)
{
    title "errors";
    
    {
        title "no zip filname";
        my $z = new Archive::Zip::SimpleUnzip ;
    
        is $z, undef ;
        is $SimpleUnzipError, "Missing Filename",
            "  missing filename";
    }
    
    if (1) 
    {
        title "directory";
        my $lex = new LexDir my $dir;
        my $z = new Archive::Zip::SimpleUnzip $dir ;
    
        is $z, undef ;
        is $SimpleUnzipError, "Illegal Filename",
            "  missing filename";
    }    
 
    {
        title "zip file in directory that doesn't exist";
        my $lex = new LexDir my $dir;
        my $zipfile = File::Spec->catfile($dir, "not", "exist", "x.zip");
        
        my $z = new Archive::Zip::SimpleUnzip $zipfile ;
    
        is $z, undef ;
        like $SimpleUnzipError, qr/cannot open file/,
            "  missing filename";
    }  
    
#    SKIP:
#    {
#        title "file not readable";
#        my $lex = new LexFile my $zipfile;
       
#        chmod 0444, $zipfile 
#            or skip "Cannot create non-readable file", 3 ;

#        skip "Cannot create non-readable file", 3 
#            if -r $zipfile ;

#        ok ! -r $zipfile, "  zip file not readable";
               
#        my $z = new Archive::Zip::SimpleUnzip $zipfile ;
   
#        is $z, undef ;
#        is $SimpleUnzipError, "Illegal Filename",
#            "  Illegal Filename";
           
#        chmod 0777, $zipfile ;           
#    }    
  
            
    {
        title "filename undef";
        my $z = new Archive::Zip::SimpleUnzip undef;
    
        is $z, undef ;
        is $SimpleUnzipError, "Illegal Filename",
            "  missing filename";
    }    
    
    if (0) # TODO
    {
        title "Bad parameter in new";
        my $lex = new LexFile my $zipfile;        
        eval { my $z = new Archive::Zip::SimpleUnzip $zipfile, fred => 1 ; };
    
        like $@,  qr/Archive::Zip::SimpleUnzip: unknown key value(s) fred at/,
            "  value  is bad";
                   
        like $SimpleUnzipError, qr/Archive::Zip::SimpleUnzip: unknown key value(s) fred at/,
            "  missing filename";
    }   
            

}

use Fcntl ':mode';

# TODO - workout available compressors
if (1)
{
    for my $method ( ZIP_CM_DEFLATE, ZIP_CM_BZIP2, ZIP_CM_STORE )
    # for my $method ( ZIP_CM_DEFLATE )
    {
        for my $comment ('', "abcde")
        # for my $comment ("abcde")
        {
            for my $streamed (0, 1) #, 1)
            {
                for my $to ( qw(filehandle filename buffer))
                # for my $to ( qw(filename)) #  filename buffer))
                {
                    for my $zip64 (0)
                    {
                        for my $utf8 (0, 1)
                        {
                            title "** TO $to, Method $method, Comment '$comment', Streamed $streamed. Zip64 $zip64";
                
                            my $lex = new LexFile my $name2 ;
                            my $output;
                            my $buffer;
                            my $zipfile;
                
                            if ($to eq 'buffer')
                            {
                                $output = $zipfile = \$buffer ; 
                            }
                            elsif ($to eq 'filename')
                            {
                                $output = $zipfile = $name2 ;
                            }
                            elsif ($to eq 'filehandle')
                            {
                                $zipfile = $name2;
                                $output = new IO::File ">$name2" ;
                            }
                        
                            my $create = 
                                [
                                    #[ Name => "fred", Payload => "abcd"],
                                    [ "fred1", "abcd1", [] ],
                                    [ "fred2", "abcd2", [Comment => "member comment"] ],
                                    [ "fred3", "abcd3", [] ],
                                    [ "fred4", "abcd4", [Utf8 => 0] ],
                                    [ "fred5", "abcd5", [Utf8 => 1] ],
                                ] ;
                    
                            createZip($zipfile, $create, { ZipComment => $comment, 
                                                        Method     => $method, 
                                                        Stream     => $streamed, 
                                                        Zip64      => $zip64,
                                                        Utf8       => $utf8
                                                        } ) ;
                        
                            my $z = new Archive::Zip::SimpleUnzip $zipfile ;
                            isa_ok $z, "Archive::Zip::SimpleUnzip";
                    
                            {
                                title "Names";
                                is $z->names(), scalar(@$create), "correct number of entries in zip file";
                                is_deeply [ $z->names() ], [ map { $_->[0] } @$create ], "names ok" ;
                            }
                            {
                                title "zip comment";
                                is $z->comment(), $comment, "Zip comment is '$comment'";
                            }
                        
                            {
                                title "Exists";
                                ok $z->exists("fred5"), "fred5 exists";
                                ok ! $z->exists("fred6"), "fred6 does not exist";
                            }
                        
                            my $element ;
                            my @got = ();
                            my $payload = '';
                            my $index = 0;
                        
                            {
                                my $input = $create->[$index ++] ;
                                my $name = $input->[0];
                                my $expected = $input->[1];                    
                            
                                $element = $z->next();
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->name(), $name, "Name is '$name'";
                                is $element->comment(), "", "No comment in '$name";
                                is $element->content(), $expected, "Payload ok in '$name'";
                                is $element->utf8(), $utf8, "Utf8 ok in '$name'";
                                ok $element->close();
                            }
                        
                            {
                                my $input = $create->[$index ++] ;
                                my $name = $input->[0];
                                my $expected = $input->[1];                    
                                                
                                my $element = $z->next();
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->name(), $name, "Name is '$name'";
                                is $element->comment(), "member comment", "comment ok in '$name'";
                                is $element->utf8(), $utf8, "Utf8 ok in '$name'";
                            
                                my $fh = $element->open();
                                isa_ok $fh, "Archive::Zip::SimpleUnzip::Handle";
                                ok !$fh->eof(), "!eof";
                                ok ! eof($fh), "!eof";
                                is tell($fh), 0, "tell == 0";
                                is $fh->tell(), 0, "tell == 0";
                            
                                is $fh->read($payload, 1024), length($expected); 
                                is tell($fh), length($expected), "tell == 5"
                                    or diag $SimpleUnzipError ;
                                ok $fh->eof(), "eof";
                                ok eof($fh), "eof";  
                                
                                is $payload, $expected, "payload ok in '$name'";
                            }
                        
                            {
                                my $input = $create->[$index ++] ;
                                my $name = $input->[0];
                                my $expected = $input->[1];
                                                
                                $element = $z->next();
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->name(), $name, "Name is '$name'";
                                is $element->comment(), "", "No comment in '$name'";                    
                                is $element->utf8(), $utf8, "Utf8 ok in '$name'";
                                my $fh = $element->open();
                                is $fh->tell(), 0;
                                ok !$fh->eof();        
                                local $/;
                                $payload = <$fh>;
                                ok $fh->eof();
                                is $fh->tell(), length($expected);        
                                is $payload, $expected, "Payload ok in '$name'";
                            }

                            {
                                my $input = $create->[$index ++] ;
                                my $name = $input->[0];

                                $element = $z->next();
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->utf8(), 0, "Utf8 ok in '$name'";
                            }

                            {
                                my $input = $create->[$index ++] ;
                                my $name = $input->[0];

                                $element = $z->next();
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->utf8(), 1, "Utf8 ok in '$name'";
                            }

                            {
                                $element = $z->next();
                                ok ! defined $element, "No next";
                            }
                        
                            {
                                my $input = $create->[0] ;
                                my $name = $input->[0];  
                                my $expected = $input->[1];

                                my $element = $z->member($name);
                                isa_ok $element, "Archive::Zip::SimpleUnzip::Member";
                                is $element->name(), $name, "Name is '$name'";
                                my $fh = $element->open();
                                is $fh->tell(), 0;
                                ok !$fh->eof();  
                                my $payload = '';
                                my $x;

                                my $ix = 1; 
                                while ($fh->read($x, 1))
                                {
                                    $payload .= $x ;
                                    is $fh->tell(), $ix ++;
                                }
                                ok $fh->eof();   
                                is $fh->tell(), length($expected);                            
                                is $payload, $expected, "Payload ok in '$name'";
                            }

                            {
                                # member that does not exist

                                my $name = "not-there" ;
                                my $element = $z->member($name);
                                isnt $element, "Archive::Zip::SimpleUnzip::Member";
                                ok ! $element, "element object false";
                                is $SimpleUnzipError, "Member '$name' not in zip" ;
                            }

                            ok $z->close, "closed ok";
                        }
                    }
                            
                }
            }   
        }
    }
}

my $TestZipsDir = "./t/test-zips/";

SKIP:
{
    skip "Skipping BIG tests", 67
        if ! -d $TestZipsDir;

    if (1)
    {
        title "Zip file with exactly 64k members (but not Zip64)" ;

        my $z = new Archive::Zip::SimpleUnzip "$TestZipsDir/test64k-notzip64.zip" ;
        isa_ok $z, "Archive::Zip::SimpleUnzip";

        my $expectedMembers = 0xFFFF;

        is $z->names(), $expectedMembers, "Exactly $expectedMembers members in zip" ;

        my $index = 1 ;
        while (my $member = $z->next())
        {
            last if $member->name() ne "$index" ;
            last if $member->content() ne "$index" ;
            ++ $index ;
        }

        is $index, $expectedMembers+1, "Matched with $expectedMembers";
    }


    if (1)
    {
        title "Zip file with exactly 64k members (is Zip64)" ;

        my $z = new Archive::Zip::SimpleUnzip "$TestZipsDir/test64k.zip" ;
        isa_ok $z, "Archive::Zip::SimpleUnzip";

        my $expectedMembers = 0xFFFF;

        is $z->names(), $expectedMembers, "Exactly $expectedMembers members in zip" ;

        my $index = 1 ;
        while (my $member = $z->next())
        {
            last if $member->name() ne "$index" ;
            last if $member->content() ne  "$index" ;
            ++ $index ;
        }

        is $index, $expectedMembers+1, "Matched with $expectedMembers";
    }


    if (1)
    {
        title "Zip file with  64k + 1 members (must be Zip64)" ;

        my $z = new Archive::Zip::SimpleUnzip "$TestZipsDir/test64k-plus1.zip" ;
        isa_ok $z, "Archive::Zip::SimpleUnzip";

        my $expectedMembers = 0xFFFF + 1;

        is $z->names(), $expectedMembers, "Exactly $expectedMembers members in zip" ;

        my $index = 1 ;
        while (my $member = $z->next())
        {
            last if $member->name() ne "$index" ;
            last if $member->content() ne  "$index" ;
            ++ $index ;
        }

        is $index, $expectedMembers+1, "Matched with $expectedMembers";
    }


    # SKIP:
    if (1)
    {
        my $max32 = 0xFFFFFFFF;
        my @inputs = ( 
                    # Fist file > 4Gig, plus a small file
                    [ "big1.zip", "zipcomment", 
                                        ["first",   "",  [$max32 +1, $max32+1] ], 
                                        ["second", "c2", "data"                 ],  
                    ],
                    # Combination of files makes archive > 4Gig
                    [ "big2.zip", "", ["first",   "",  [0x80000000, 0x80000000] ], 
                                        ["second", "",   "data"                   ],
                                        ["third",  "",   [0x80000000, 0x80000000]],
                                        ["fourth",  "",  "fore"],  
                    ],
                    # Uncompressed size >4 Gig, compressed <4Gig
                    [ "big3.zip", "", ["zeros",   "",  [$max32+101, 0x003F99DD ] ],                                         
                    ],
                    # Empry archive - Only thing present is end central header, with zero entries
                    [ "empty.zip", "", 
                    ],
                    # Empry archive - Only thing present is end central header, with zero entries
                    [ "empty-with-comment.zip", "zipcomment", 
                    ],                   

        ) ;

        for my $in (@inputs)
        {
            my $zipfile = $TestZipsDir . shift @$in;
            my $comment = shift @$in;
            my $entries = @$in ;
            my @names   = map { $_->[0] } @$in ;

            my $z = new Archive::Zip::SimpleUnzip $zipfile ;
            isa_ok $z, "Archive::Zip::SimpleUnzip", "created object for file $zipfile";
            is $z->names(), $entries, "Has $entries members";
            is_deeply [ $z->names() ], [ @names ], "names are ok" ;
            is $z->comment(), $comment, "Zip comment is '$comment'";
            for my $m (@$in)
            {
                my $mname = shift @$m;
                my $mcomment = shift @$m;
                my $payload = shift @$m;

                my $member = $z->member($mname);
                isa_ok $member, "Archive::Zip::SimpleUnzip::Member";
                is $member->name(), $mname, "Member Name is '$mname'" ;
                is $member->comment(), $mcomment, "Member Comment is '$mcomment'";
                if (ref $payload eq 'ARRAY')
                {
                    # check lengths
                    my $uncompSize = shift @$payload;
                    my $compSize = shift @$payload;
                    is $member->uncompressedSize(), $uncompSize, "uncompressedSize is $uncompSize";
                    is $member->compressedSize(), $compSize, "compressedSize is $compSize";
                }
                else
                {       
                    is $member->content(), $payload, "Payload ok";
                    is $member->uncompressedSize(), length($payload), "uncompressedSize is ";
                }
            }
        } 
    }

}

exit;