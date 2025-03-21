#!/usr/bin/perl
#
# DW::Logic::ProfilePage
#
# This module provides logic for rendering the profile page for various types
# of accounts.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::ProfilePage;

use strict;
use DW::Countries;
use DW::Logic::UserLinkBar;
use DW::External::ProfileServices;

# returns a new profile page object
sub profile_page {
    my ( $u, $remote, %opts ) = @_;
    $u = LJ::want_user($u) or return undef;

    # remote may be undef, OR a valid object
    return undef
        if defined $remote && !LJ::isu($remote);

    my $viewall = $opts{viewall} ? $opts{viewall} : 0;

    # sprinkle holy water
    my $self = { u => $u, remote => $remote, viewall => $viewall };
    bless $self, __PACKAGE__;
    return $self;
}
*LJ::User::profile_page = \&profile_page;
*DW::User::profile_page = \&profile_page;

# returns array of hashrefs
#   (
#       { url => "http://...",
#         title => "Something"
#         image => "http://...",
#         text => "More Text",
#         class => ".css.class",
#       },
#       { ... },
#       ...
#   )
sub action_links {
    my $self = $_[0];

    my $u      = $self->{u};
    my $remote = $self->{remote};

    my $user_link_bar = $u->user_link_bar( $remote, class_prefix => "profile" );
    my @ret           = $user_link_bar->get_links(
        "manage_membership", "trust",   "watch",  "post",
        "track",             "message", "search", "buyaccount"
    );
    return \@ret;
}

# returns hashref with userpic display options
#  {
#     userpic      => 'http://...',
#     userpic_url  => 'http://...',    # OPTIONAL
#     caption_text => 'Edit',          # OPTIONAL
#     caption_url  => 'http://...',    # OPTIONAL
#     imgtag       => HTML to display
#  }
sub userpic {

    my $self = $_[0];

    my $u      = $self->{u};
    my $user   = $u->user;
    my $remote = $self->{remote};
    my $ret    = {};

    # syndicated accounts have a very simple thing
    if ( $u->is_syndicated ) {
        $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/feed.png";
    }
    else {

        # determine what picture URL to use
        if ( my $up = $u->userpic ) {
            $ret->{userpic} = $up->url;
        }
        elsif ( $u->is_personal ) {
            $ret->{userpic}  = "$LJ::IMGPREFIX/profile_icons/user.png";
            $ret->{alt_text} = _profile_ml('.userpic.user.alt');
            $ret->{width}    = 100;
            $ret->{height}   = 100;
        }
        elsif ( $u->is_community ) {
            $ret->{userpic}  = "$LJ::IMGPREFIX/profile_icons/comm.png";
            $ret->{alt_text} = _profile_ml('.userpic.comm.alt');
            $ret->{width}    = 100;
            $ret->{height}   = 100;
        }
        elsif ( $u->is_identity ) {
            $ret->{userpic}  = "$LJ::IMGPREFIX/profile_icons/openid.png";
            $ret->{alt_text} = _profile_ml('.userpic.openid.alt');
            $ret->{width}    = 100;
            $ret->{height}   = 100;
        }

        # now determine what caption text to show
        if ( $remote && $remote->can_manage($u) ) {
            if ( $u->get_userpic_count ) {
                $ret->{userpic_url}  = $u->allpics_base;
                $ret->{caption_text} = _profile_ml('.section.edit');
                $ret->{caption_url}  = "$LJ::SITEROOT/manage/icons?authas=$user";
            }
            else {
                $ret->{userpic_url}  = "$LJ::SITEROOT/manage/icons?authas=$user";
                $ret->{caption_text} = _profile_ml('.userpic.upload');
                $ret->{caption_url}  = "$LJ::SITEROOT/manage/icons?authas=$user";
            }
        }
        else {
            if ( $u->get_userpic_count ) {
                $ret->{userpic_url} = $u->allpics_base;
            }
        }
    }

    # build the HTML tag
    my $userpic_obj = LJ::Userpic->get( $u, $u->{defaultpicid} );
    my $imgtag_conditional;
    if ($userpic_obj) {
        $imgtag_conditional = $userpic_obj->imgtag;
    }
    else {
        my $ret_userpic  = $ret->{userpic}  || '';
        my $ret_height   = $ret->{height}   || '';
        my $ret_width    = $ret->{width}    || '';
        my $ret_alt_text = $ret->{alt_text} || '';

        $imgtag_conditional =
            qq{<img src="$ret_userpic" height=$ret_height width=$ret_width alt="$ret_alt_text" />};
    }

    #  Set the wrapper materials to surrounded the  userpic image
    my ( $apre, $apost ) = ( '', '' );
    if ( $ret->{userpic_url} ) {
        $apre  = "<a href='" . LJ::ehtml( $ret->{userpic_url} ) . "'>";
        $apost = "</a>";
    }

    # Set the HTML to display the userpic
    if ( $ret->{caption_text} ) {
        $apost .= qq(
            <br />
            <span class="user_pic_caption">
                [<a href="$ret->{caption_url}">$ret->{caption_text}</a>]
            </span>
        );
    }

    $ret->{imgtag} = $apre . $imgtag_conditional . $apost;

    return $ret;
}

# returns an array of journal warnings
#   (
#       { class => 'someclass',
#         text => 'Some Warning',
#        },
#       ...
#   )
sub warnings {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    if ( $u->is_locked ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml('statusvis_message.locked') };
    }
    elsif ( $u->is_memorial ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml('statusvis_message.memorial') };
    }
    elsif ( $u->is_readonly ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml('statusvis_message.readonly') };
    }

    unless ( $u->is_identity ) {
        if ( $u->adult_content_calculated eq 'explicit' ) {
            push @ret,
                {
                class => 'journal_adult_warning',
                text  => _profile_ml('.details.warning.explicit')
                };
        }
        elsif ( $u->adult_content_calculated eq 'concepts' ) {
            push @ret,
                {
                class => 'journal_adult_warning',
                text  => _profile_ml('.details.warning.concepts')
                };
        }
    }

    return \@ret;
}

# returns an array of comment statistic strings
sub comment_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $num_comments_received = $u->num_comments_received;
    my $num_comments_posted   = $u->num_comments_posted;

    push @ret,
        _profile_ml( '.details.comments.received2',
        { num_raw => $num_comments_received, num_comma => LJ::commafy($num_comments_received) } )
        unless $u->is_identity;
    push @ret,
        _profile_ml( '.details.comments.posted2',
        { num_raw => $num_comments_posted, num_comma => LJ::commafy($num_comments_posted) } )
        if LJ::is_enabled('show-talkleft') && ( $u->is_personal || $u->is_identity );

    return \@ret;
}

# returns an array of support statistic strings
sub support_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $supportpoints = $u->support_points_count;
    push @ret,
        _profile_ml( '.details.supportpoints2',
        { aopts => qq{href="$LJ::SITEROOT/support/"}, num => LJ::commafy($supportpoints) } )
        if $supportpoints;

    return \@ret;
}

# return array of entry statistic strings
sub entry_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = $u->number_of_posts;
    push @ret,
        _profile_ml(
        '.details.entries3',
        {
            num_raw   => $ct,
            num_comma => LJ::commafy($ct),
            aopts     => 'href="' . $u->journal_base . '"',
        }
        ) unless $u->is_identity;

    return \@ret;
}

# return array of tag statistic strings
sub tag_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = scalar keys %{ $u->tags || {} };
    push @ret,
        _profile_ml(
        '.details.tags2',
        {
            num_raw   => $ct,
            num_comma => LJ::commafy($ct),
            aopts     => 'href="' . $u->journal_base . '/tag/"',
        }
        ) unless $u->is_identity || $u->is_syndicated;

    return \@ret;
}

# return array of memory statistic strings
sub memory_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = LJ::Memories::count( $u->id ) || 0;
    push @ret,
        _profile_ml(
        '.details.memories2',
        {
            num_raw   => $ct,
            num_comma => LJ::commafy($ct),
            aopts     => "href='$LJ::SITEROOT/tools/memories?user=" . $u->user . "'",
        }
        ) unless $u->is_syndicated;

    return \@ret;
}

# return array of userpic statistic strings
sub userpic_stats {
    my $self = $_[0];

    my $u = $self->{u};
    return [] if $u->is_syndicated;

    my @ret = ();

    my $ct = $u->get_userpic_count;
    if ( $u->equals( $self->{remote} ) ) {
        my $slots = $u->userpic_quota;
        my $bonus = $u->prop('bonus_icons') || 0;
        push @ret,
            _profile_ml(
            '.details.userpics.self',
            {
                uploaded_raw   => $ct,
                uploaded_comma => LJ::commafy($ct),
                slots_raw      => $slots,
                slots_comma    => LJ::commafy($slots),
                bonus_raw      => $bonus,
                bonus_comma    => LJ::commafy($bonus),
                aopts          => "href='" . $u->allpics_base . "'",
            }
            );
    }
    else {
        push @ret,
            _profile_ml(
            '.details.userpics.others',
            {
                uploaded_raw   => $ct,
                uploaded_comma => LJ::commafy($ct),
                aopts          => "href='" . $u->allpics_base . "'",
            }
            );
    }

    return \@ret;
}

# returns array of hashrefs
sub basic_info_rows {
    my $self = $_[0];

    my $u   = $self->{u};
    my @ret = $self->_basic_info_display_name;

    if ( $u->is_community ) {
        push @ret, $self->_basic_info_location;
        push @ret, $self->_basic_info_website;
        push @ret, $self->_basic_info_comm_membership;
        push @ret, $self->_basic_info_comm_postlevel;
        push @ret, $self->_basic_info_comm_theme;
    }
    elsif ( $u->is_syndicated ) {
        push @ret, $self->_basic_info_syn_status;
        push @ret, $self->_basic_info_syn_readers;
    }
    else {
        push @ret, $self->_basic_info_birthday;
        push @ret, $self->_basic_info_location;
        push @ret, $self->_basic_info_website;
    }

    return \@ret;
}

# returns the account's displayed name
# available for all account types
sub _basic_info_display_name {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    my $name = $u->name_html;
    if ( $u->is_syndicated ) {
        $ret->[0] = _profile_ml('.label.syndicatedfrom');
        $ret->[1] = ' ';

        if ( my $url = $u->url ) {
            $ret->[2] = { url => LJ::ehtml($url), text => $name };
        }
        else {
            $ret->[2] = { text => $name };
        }

        my $synd = $u->get_syndicated;
        $ret->[3] = {
            url  => LJ::ehtml( $synd->{synurl} ),
            text => LJ::img( 'xml', '', { align => 'absmiddle' } ),
        };
    }
    else {
        $ret->[0] = _profile_ml('.label.name');
        $ret->[1] = $name;
    }

    return $ret;
}

# returns the account's birthday
# available only for personal and identity account types
sub _basic_info_birthday {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret unless $u->is_personal || $u->is_identity;

    if ( $u->bday_string && ( $u->can_share_bday || $self->{viewall} ) ) {
        my $bdate = $u->prop('bdate');
        if ( $bdate && $bdate ne "0000-00-00" ) {
            $ret->[0] = _profile_ml('.label.birthdate');
            $ret->[1] = $self->security_image( $u->opt_sharebday );
            my ( $year, $mon, $day ) = split /-/, $bdate;
            my $moname = LJ::Lang::month_short_ml($mon);
            $day += 0;
            if ( $u->bday_string =~ /\d+-\d+-\d+/ ) {
                $ret->[1] .= "$moname $day, $year";
            }
            elsif ( $u->bday_string =~ /\d+-\d+/ ) {
                $ret->[1] .= "$moname $day";
            }
            else {
                $ret->[1] .= $u->bday_string;
            }
        }
    }

    return $ret;
}

# returns the account's location
# available only for personal, identity, and community account types
sub _basic_info_location {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret if $u->is_syndicated;

    my ( $city, $state, $country ) = ( $u->prop('city'), $u->prop('state'), $u->prop('country') );
    my ( $city_ret, $state_ret, $country_ret );
    if ( ( $u->can_show_location || $self->{viewall} ) && ( $city || $state || $country ) ) {
        my $ecity    = LJ::eurl($city);
        my $ecountry = LJ::eurl($country);
        my $estate   = "";
        my $secimg   = $self->security_image( $u->opt_showlocation );
        my $dirurl   = "$LJ::SITEROOT/directorysearch?opt_sort=ut&amp;s_loc=1";

        if ($country) {
            my %countries = ();
            DW::Countries->load_legacy( \%countries );

            $country_ret = {};
            $country_ret->{url} = "$dirurl&amp;loc_cn=$ecountry"
                if LJ::is_enabled('directory');
            $country_ret->{text}   = $countries{$country};
            $country_ret->{secimg} = $secimg if !$state && !$city;
        }

        if ($state) {
            my %states;
            my $states_type = $LJ::COUNTRIES_WITH_REGIONS{$country}->{type};
            LJ::load_codes( { $states_type => \%states } ) if defined $states_type;

            $state  = LJ::ehtml($state);
            $state  = $states{$state} if $states_type && $states{$state};
            $estate = LJ::eurl($state);

            $state_ret = {};
            $state_ret->{url} = "$dirurl&amp;loc_cn=$ecountry&amp;loc_st=$estate"
                if $country && LJ::is_enabled('directory');
            $state_ret->{text}   = LJ::ehtml($state);
            $state_ret->{secimg} = $secimg if !$city;
        }

        if ($city) {
            $city = LJ::ehtml($city);

            $city_ret = {};
            $city_ret->{url} = "$dirurl&amp;loc_cn=$ecountry&amp;loc_st=$estate&amp;loc_ci=$ecity"
                if $country && LJ::is_enabled('directory');
            $city_ret->{text}   = $city;
            $city_ret->{secimg} = $secimg;
        }

        push @$ret, $city_ret, $state_ret, $country_ret;
        unshift @$ret, ( _profile_ml('.label.location'), ', ' );
    }

    return $ret;
}

# returns the account's website
# available only for personal, identity, and community account types
sub _basic_info_website {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret if $u->is_syndicated;

    my ( $url, $urlname ) = ( $u->url, $u->prop('urlname') );
    if ($url) {
        $url = LJ::ehtml($url);
        unless ( $url =~ /^https?:\/\// ) {
            $url =~ s/^http\W*//;
            $url = "http://$url";
        }
        $urlname = LJ::ehtml( $urlname || $url );
        if ($url) {
            $ret->[0] = _profile_ml('.label.website');
            $ret->[1] = { url => $url, text => $urlname };
        }
    }

    return $ret;
}

# returns the account's community membership
# available only for community account types
sub _basic_info_comm_membership {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    my ( $membership, $postlevel ) = $u->get_comm_settings;

    my $membership_string = _profile_ml('.commsettings.membership.open');
    if ( $membership && $membership eq "moderated" ) {
        $membership_string = _profile_ml('.commsettings.membership.moderated');
    }
    elsif ( $membership && $membership eq "closed" ) {
        $membership_string = _profile_ml('.commsettings.membership.closed');
    }

    $ret->[0] = _profile_ml('.commsettings.membership.header');
    $ret->[1] = $membership_string;

    return $ret;
}

# returns the account's community posting level
# available only for community account types
sub _basic_info_comm_postlevel {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    my ( $membership, $postlevel ) = $u->get_comm_settings;

    my $postlevel_string = _profile_ml('.commsettings.postlevel.members');
    if ( $postlevel && $postlevel eq "select" ) {
        $postlevel_string = _profile_ml('.commsettings.postlevel.select');
    }
    elsif ( $u->prop('nonmember_posting') ) {
        $postlevel_string = _profile_ml('.commsettings.postlevel.anybody');
    }

    $postlevel_string .= _profile_ml('.commsettings.postlevel.moderated') if $u->prop('moderated');

    $ret->[0] = _profile_ml('.commsettings.postlevel.header');
    $ret->[1] = $postlevel_string;

    return $ret;
}

# returns the account's community theme
# available only for community account types
sub _basic_info_comm_theme {
    my $self = $_[0];

    my $u   = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    if ( $u->prop('comm_theme') ) {
        $ret->[0] = _profile_ml('.commdesc.header');
        $ret->[1] = LJ::ehtml( $u->prop('comm_theme') );
    }

    return $ret;
}

# returns the account's feed status
# available only for syndication account types
sub _basic_info_syn_status {
    my $self = $_[0];

    my $u = $self->{u};

    my $ret = [];
    return $ret unless $u->is_syndicated;

    my $synd = $u->get_syndicated;
    my $syn_status;

    $syn_status .= _profile_ml('.syn.lastcheck') . " ";
    $syn_status .= $synd->{lastcheck} || _profile_ml('.syn.last.never');
    my $status = {
        parseerror  => "Parse error",
        notmodified => "Not modified",
        toobig      => "Too big",
        posterror   => "Posting error",
        ok          => "",                # no status line necessary
        nonew       => "",                # no status line necessary
    }->{ $synd->{laststatus} // 'ok' };
    $syn_status .= " ($status)" if $status;

    if ( $synd->{laststatus} && $synd->{laststatus} eq 'parseerror' ) {
        $syn_status .=
              "<br />"
            . _profile_ml('.syn.parseerror') . " "
            . LJ::ehtml( $u->prop('rssparseerror') );
    }

    $syn_status .= "<br />" . _profile_ml('.syn.nextcheck') . " $synd->{checknext}";

    $ret->[0] = _profile_ml('.label.syndicatedstatus');
    $ret->[1] = $syn_status;

    return $ret;
}

# returns the account's feed readers
# available only for syndication account types
sub _basic_info_syn_readers {
    my $self = $_[0];

    my $u = $self->{u};

    my $ret = [];
    return $ret unless $u->is_syndicated;

    $ret->[0] = _profile_ml('.label.syndreadcount');
    $ret->[1] = scalar $u->watched_by_userids;

    return $ret;
}

# returns various methods of contacting the user
sub contact_rows {
    my $self = $_[0];

    my $u      = $self->{u};
    my $remote = $self->{remote};
    my @ret    = ();

    # private message
    if ( ( $u->is_personal || $u->is_identity ) && $remote && $u->can_receive_message($remote) ) {
        push @ret,
            {
            url  => "$LJ::SITEROOT/inbox/compose?user=" . $u->user,
            text => _profile_ml('.contact.pm')
            };
    }

    # email
    if ( ( !$u->is_syndicated && $u->share_contactinfo($remote) ) || $self->{viewall} ) {
        my @emails = $u->emails_visible($remote);
        my $secimg = $self->security_image( $u->opt_showcontact )
            if @emails;
        foreach my $email (@emails) {
            push @ret,
                {
                email  => $email,
                secimg => $secimg
                };
        }
    }

    return \@ret;
}

# returns the bio
sub bio {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret;

    if ( $ret = $u->bio ) {
        if ( $u->is_identity ) {
            $ret = LJ::ehtml($ret);    # XXXXX FIXME: TEMP FIX
            $ret =~ s!\n!<br />!g;
        }
        else {
            LJ::CleanHTML::clean_userbio( \$ret, $u->email_status eq "N" );
        }

        LJ::EmbedModule->expand_entry( $u, \$ret );
    }

    return $ret;
}

# returns an array of interests
sub interests {
    my $self = $_[0];

    my $u      = $self->{u};
    my $remote = $self->{remote};
    my @ret;

    my $ints = $u->get_interests();    # arrayref of: [ intid, intname, intcount ]
    if (@$ints) {
        foreach my $int (@$ints) {
            my $intid    = $int->[0];
            my $intname  = $int->[1];
            my $intcount = $int->[2];

            LJ::text_out( \$intname );
            my $eint = LJ::eurl($intname);
            if ( $intcount > 1 ) {

                # bold shared interests on all profiles except your own
                if ( $remote && !$remote->equals($u) ) {
                    my %remote_intids =
                        map { $_ => 1 } @{ $remote->get_interests( { justids => 1 } ) };
                    $intname = "<strong>$intname</strong>" if $remote_intids{$intid};
                }
                push @ret, { url => "$LJ::SITEROOT/interests?int=$eint", text => $intname };
            }
            else {
                push @ret, $intname;
            }
        }
    }

    return \@ret;
}

# return an array of external services (mostly IM services)
sub external_services {
    my $self = $_[0];

    my $u      = $self->{u};
    my $remote = $self->{remote};
    my @ret;

    return [] unless $u->is_personal && ( $u->share_contactinfo($remote) || $self->{viewall} );

    my $info = sub {
        my ( $acct, $site ) = @_;

        my $url =
            defined $site->{url_format}
            ? sprintf( $site->{url_format}, LJ::eurl($acct) )
            : undef;

        return {
            type     => $site->{name},
            text     => LJ::ehtml($acct),
            url      => $url,
            image    => $site->{imgfile},
            title_ml => $site->{title_ml},
        };
    };

    my $services = DW::External::ProfileServices->list;
    my $accounts = $u->load_profile_accts;

    if (%$accounts) {
        foreach my $site (@$services) {
            my $s_id = $site->{service_id};
            my $vals = $accounts->{$s_id} // [];

            foreach my $acct (@$vals) {
                push @ret, $info->( $acct->[1], $site );
            }
        }

        return \@ret;
    }

    # legacy path for users who still have data in userprops
    my $userprops = DW::External::ProfileServices->userprops;

    $u->preload_props(@$userprops);

    foreach my $site (@$services) {
        next unless defined $site->{userprop};
        if ( my $acct = $u->prop( $site->{userprop} ) ) {
            push @ret, $info->( $acct, $site );
        }
    }

    return \@ret;
}

# returns whether a given list should be hidden or not
sub hide_list {
    my ( $self, $list ) = @_;

    my $u      = $self->{u};
    my $remote = $self->{remote};

    return 1 if $list =~ /^posting_access/;

    return $u->prop('opt_hidememberofs') if $list =~ /of_comms$/;

    return 1 if $u->prop('opt_hidefriendofs');
    return 0;
}

# returns all userids that are trusted but that don't trust in return
sub not_mutually_trusted_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return [] unless $u->is_personal;

    my @trusted_userids = $u->trusted_userids;
    my %is_trusted_by   = map { $_ => 1 } $u->trusted_by_userids;

    foreach my $uid (@trusted_userids) {
        push @ret, $uid if !$is_trusted_by{$uid};
    }

    return \@ret;
}

# returns all userids that trust but that aren't trusted in return
sub not_mutually_trusted_by_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return [] unless $u->is_personal;

    my @trusted_by_userids = $u->trusted_by_userids;
    my %is_trusted         = map { $_ => 1 } $u->trusted_userids;

    foreach my $uid (@trusted_by_userids) {
        push @ret, $uid if !$is_trusted{$uid};
    }

    return \@ret;
}

# returns all userids that are watched but that don't watch in return
sub not_mutually_watched_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return [] unless $u->is_personal || $u->is_identity;

    my @watched_userids = $u->watched_userids;
    my %is_watched_by   = map { $_ => 1 } $u->watched_by_userids;

    foreach my $uid (@watched_userids) {
        push @ret, $uid if !$is_watched_by{$uid};
    }

    return \@ret;
}

# returns all userids that watch but that aren't watched in return
sub not_mutually_watched_by_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return [] unless $u->is_personal || $u->is_identity;

    my @watched_by_userids = $u->watched_by_userids;
    my %is_watched         = map { $_ => 1 } $u->watched_userids;

    foreach my $uid (@watched_by_userids) {
        push @ret, $uid if !$is_watched{$uid};
    }

    return \@ret;
}

# identical to user method except returns a reference instead of a list
sub maintainer_userids {
    my $self = $_[0];
    return [ $self->{u}->maintainer_userids ];
}

# identical to user method except returns a reference instead of a list
sub member_userids {
    my $self = $_[0];
    return [ $self->{u}->member_userids ];
}

# identical to user method except returns a reference instead of a list
sub member_of_userids {
    my $self = $_[0];
    return [ $self->{u}->member_of_userids ];
}

# identical to user method except returns a reference instead of a list
sub moderator_userids {
    my $self = $_[0];
    return [ $self->{u}->moderator_userids ];
}

# identical to user method except returns a reference instead of a list
sub mutually_trusted_userids {
    my $self = $_[0];
    return [ $self->{u}->mutually_trusted_userids ];
}

# identical to user method except returns a reference instead of a list
sub mutually_watched_userids {
    my $self = $_[0];
    return [ $self->{u}->mutually_watched_userids ];
}

# identical to user method except returns a reference instead of a list
sub trusted_userids {
    my $self = $_[0];
    return [ $self->{u}->trusted_userids ];
}

# identical to user method except returns a reference instead of a list
sub trusted_by_userids {
    my $self = $_[0];
    return [ $self->{u}->trusted_by_userids ];
}

# identical to user method except returns a reference instead of a list
sub watched_userids {
    my $self = $_[0];
    return [ $self->{u}->watched_userids ];
}

# identical to user method except returns a reference instead of a list
sub watched_by_userids {
    my $self = $_[0];
    return [ $self->{u}->watched_by_userids ];
}

# convenience method
sub admin_of_userids {
    my $self = $_[0];
    return LJ::load_rel_target_cache( $self->{u}, 'A' );
}

# convenience method
sub posting_access_from_userids {
    my $self = $_[0];
    return LJ::load_rel_user_cache( $self->{u}, 'P' );
}

# convenience method
sub posting_access_to_userids {
    my $self = $_[0];
    return LJ::load_rel_target_cache( $self->{u}, 'P' );
}

# returns data hash mapping various userid lists
sub populate_edges {
    my $profile = $_[0];
    my $u       = $profile->{u};
    my $remote  = $profile->{remote};
    my %edges;

    my $force_empty = exists $LJ::FORCE_EMPTY_SUBSCRIPTIONS{ $u->id } ? 1 : 0;

    # identity accounts ignore show_mutualfriends for trust edges
    # (they can be trusted but can't trust back)
    $edges{trusted_by} = $profile->trusted_by_userids if $u->is_identity;

    # show_mutualfriends can only be true for personal or identity accounts
    if ( $u->show_mutualfriends ) {
        if ( $u->is_personal ) {
            $edges{mutually_trusted}        = $profile->mutually_trusted_userids;
            $edges{not_mutually_trusted}    = $profile->not_mutually_trusted_userids;
            $edges{not_mutually_trusted_by} = $profile->not_mutually_trusted_by_userids;
        }
        $edges{mutually_watched}        = $profile->mutually_watched_userids;
        $edges{not_mutually_watched}    = $profile->not_mutually_watched_userids;
        $edges{not_mutually_watched_by} = $profile->not_mutually_watched_by_userids;

        # need this one to get watched communities and feeds
        $edges{watched} = $profile->watched_userids;
    }
    else {    # no show_mutualfriends, includes communities
        if ( $u->is_personal ) {
            $edges{trusted}    = $profile->trusted_userids;
            $edges{trusted_by} = $profile->trusted_by_userids;
        }
        if ( $u->is_individual ) {
            $edges{watched} = $profile->watched_userids;
        }

        # respect option to hide watched_by unless journal owner == remote
        my $hide_watched_by = 0;
        unless ( $remote && $remote->can_manage($u) ) {
            $hide_watched_by = $u->prop('opt_hidefriendofs') ? 1 : 0;
        }

        # but ALWAYS hide watched_by if journal in the force_empty list
        unless ( $force_empty || $hide_watched_by ) {
            $edges{watched_by} = $profile->watched_by_userids;
        }
    }

    if ( $u->is_community && !$force_empty ) {
        $edges{members}             = $profile->member_userids;
        $edges{posting_access_from} = $profile->posting_access_from_userids;
    }

    if ( $u->is_personal ) {
        $edges{member_of}         = $profile->member_of_userids;
        $edges{admin_of}          = $profile->admin_of_userids;
        $edges{posting_access_to} = $profile->posting_access_to_userids;
    }

    # before returning, filter out any banned users
    my %banned_users = map { $_ => 1 } @{ LJ::load_rel_user( $u, 'B' ) || [] };
    foreach my $e ( keys %edges ) {
        $edges{$e} = [ grep { !$banned_users{$_} } @{ $edges{$e} } ];
    }

    return \%edges;
}

# returns image link based on privacy settings
sub security_image {
    my ( $self, $code ) = @_;
    my %img = (
        R => [ 'registered', 'identity/user.png' ],
        F => [ 'trusted',    'entry/locked.png' ],
        N => [ 'private',    'entry/private.png' ],
    );
    return '' unless $img{$code};
    my ( $text, $imgfile ) = @{ $img{$code} };
    $text    = LJ::Lang::ml('entryform.security') . " $text";
    $imgfile = "$LJ::SITEROOT/img/silk/$imgfile";
    return "&nbsp;(<img alt='$text' title='$text' width='16' height='16'"
        . " style='vertical-align: bottom' src='$imgfile' />)&nbsp;&nbsp;";
}

# explicitly scope the profile page for ml strings
sub _profile_ml {
    my ( $string, $optref ) = @_;
    my $page = "/profile/logic.tt";
    return LJ::Lang::ml( "$page$string", $optref );
}

1;
