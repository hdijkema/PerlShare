#!/usr/bin/perl
use strict;
use threads;
use Thread::Queue;
use Glib qw(TRUE FALSE);
use Gtk2 qw/-init -threads-init 1.050/;
use Tray;
use Shares;
use Unison;
use PerlShareCommon::Dirs;
use PerlShareCommon::Str;
use PerlShareCommon::Log;

use sigtrap qw(die normal-signals);

die "Glib::Object thread safetly failed"
	unless Glib::Object->set_threadsafe (TRUE);
	
log_file(log_dir()."/perlshare.log");

######################################################################################
# Main 
######################################################################################

my $os = $^O;

if ($os eq "darwin") {
  my $app=new Gtk2::OSXApplication();
  my $menubar=Gtk2::MenuBar->new();
  my $menu=Gtk2::Menu->new();
  my $item=Gtk2::MenuItem->new_with_label("Info");
  $item->set_submenu($menu);
  my $about=Gtk2::MenuItem->new_with_label("About");
  $menu->append($about);
  $menubar->append($item);
  $about->show();
  $item->show();
  $menu->show();
  $menubar->show();
  $app->set_menu_bar($menubar);
  $app->ready();
}

# Global menu
my $shares = new Shares();
my $menu = Gtk2::Menu->new();
my $status_icon = new Tray(images_dir(), $menu, "appindicator");

my $data_queue = new Thread::Queue();
Glib::Timeout->add(100, sub {
    my $data = $data_queue->dequeue_nb();
    while (defined($data) && $data ne "quit") {
      $data = $data_queue->dequeue_nb();
      my ($share, $state, $code) = split(/,/,$data);

      if ($code > 0) {
        $shares->associate($share, "code", $code);
      } 
      $status_icon->set_collision($code > 0);
  
      if ($state eq "starting") {
        $status_icon->begin_sync();
      } elsif ($state eq "running") {
        $status_icon->activity();
      } elsif ($state eq "done") {
        $shares->associate($share, "code", $code);
        my @S = $shares->get_shares();
        
        my $red = 0;
        foreach my $sharename (@S) {
          my $code = $shares->get_assoc($sharename, "code");
          log_info("$sharename - code = $code");
          if ($code > 0) { $red = 1; }
        }
        $status_icon->set_collision($red);
        $status_icon->end_sync();
        
        my $image_menu_item = $shares->get_assoc($share,"menu-item");
        my $img = ($code > 0) ? image_nok() : image_ok();
        $image_menu_item->set_image($img);
      }
    }
    if ($data eq "quit") {
      return 0;
    } else {
      return 1;
    }
});

create_menu($shares, $status_icon, $data_queue);
$shares->synchronizer(sub { report_cb(@_, $data_queue); });

Gtk2::main(undef);

######################################################################################
# Supporting functions
######################################################################################
  
sub create_menu($$$) {
  my $shares = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $menu = Gtk2::Menu->new();
  
  my $mnu_create_share = Gtk2::MenuItem->new("_Create share");
  my $mnu_quit = Gtk2::MenuItem->new("_Quit");
  
  $menu->append($mnu_create_share);
  $menu->append(Gtk2::SeparatorMenuItem->new());
  
  my @S = $shares->get_shares();
  foreach my $share (@S) {
    my $mnu = Gtk2::ImageMenuItem->new($share);
    my $img = image_ok();
    $mnu->set_image($img);
    my $submenu = Gtk2::Menu->new();
    my $mnu_drop = Gtk2::MenuItem->new("_Drop share");
    my $mnu_web = Gtk2::MenuItem->new("_Website");
    my $mnu_col = Gtk2::MenuItem->new("_Resolve collision");
    
    $submenu->append($mnu_col);
    $submenu->append($mnu_web);
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    $submenu->append($mnu_drop);
    $mnu_col->signal_connect("activate", sub { share_collision($shares,$share); });
    $mnu_web->signal_connect("activate", sub { share_web($shares,$share); });
    $mnu_drop->signal_connect("activate", sub { share_drop($shares,$share); });
    
    $mnu->set_submenu($submenu);
    $menu->append($mnu);
    
    $shares->associate($share,"menu-item",$mnu);
  }
  
  $menu->append(Gtk2::SeparatorMenuItem->new());
  $menu->append($mnu_quit);
  
  $mnu_quit->signal_connect("activate", sub { quit($shares); });
  $mnu_create_share->signal_connect("activate", sub { create_share($shares, $status_icon, $data_queue); });
  
  $menu->show_all();
  
  $status_icon->set_menu($menu);
  
  return $menu;
}

sub image_ok() {
  return Gtk2::Image->new_from_file(images_dir()."/tray_inactive.png");
}

sub image_nok() {
  return Gtk2::Image->new_from_file(images_dir()."/tray_collision.png");
}

sub quit($) {
  my $shares = shift;
  Gtk2::main_quit();
}

######################################################################
# Create share
######################################################################

sub create_share($$) {
  my $shares = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $dialog = Gtk2::Dialog->new();
  $dialog->set_title("PerlShare - Create Share");
  
  my $lbl_share = Gtk2::Label->new("The Name of the Share:");
  my $lbl_server = Gtk2::Label->new("PerlShare Server Hostname:");
  my $lbl_email = Gtk2::Label->new("Your registered email adress:");
  my $lbl_pass = Gtk2::Label->new("Your registered password:");
  my $chk_local = Gtk2::CheckButton->new("Create share under different local name:");
  $lbl_share->set_alignment(0.0, 0.5);
  $lbl_server->set_alignment(0.0, 0.5);
  $lbl_email->set_alignment(0.0, 0.5);
  $lbl_pass->set_alignment(0.0, 0.5);
  
  my $entry_share = Gtk2::Entry->new();
  my $entry_server = Gtk2::Entry->new();
  my $entry_email = Gtk2::Entry->new();
  my $entry_pass = Gtk2::Entry->new();
  my $entry_local = Gtk2::Entry->new();
  $entry_pass->set_visibility(0);
  $entry_local->set_editable(0);
  $entry_local->set_sensitive(0);
  $chk_local->signal_connect("toggled", sub { 
    $entry_local->set_editable($chk_local->get_active());
    $entry_local->set_sensitive($chk_local->get_active());
  });
  
  my $table = Gtk2::Table->new(4,2);
  $table->attach_defaults($lbl_share, 0, 1, 0, 1);
  $table->attach_defaults($chk_local, 0, 1, 1, 2);
  $table->attach_defaults($lbl_server, 0, 1, 2, 3);
  $table->attach_defaults($lbl_email, 0, 1, 3, 4);
  $table->attach_defaults($lbl_pass, 0, 1, 4, 5);
  $table->attach_defaults($entry_share, 1, 2, 0, 1);
  $table->attach_defaults($entry_local, 1, 2, 1, 2);
  $table->attach_defaults($entry_server, 1, 2, 2, 3);
  $table->attach_defaults($entry_email, 1, 2, 3, 4);
  $table->attach_defaults($entry_pass, 1, 2, 4, 5);
  
  my $vbox = $dialog->vbox;
  my $frame = Gtk2::Frame->new();
  $frame->add($table);
  $vbox->pack_start($frame,0,0,4);
  
  $vbox->show_all();
  
  $dialog->add_button("_Cancel", 0);
  $dialog->add_button("_Create", 1);
  my $response = 2;
  
  while ($response == 2) {
    $response = $dialog->run();
    if ($response == 0) {
      # do nothing
    } else {
      my $sharename = trim($entry_share->get_text());
      my $host = trim($entry_server->get_text());
      my $email = trim($entry_email->get_text());
      my $pass = trim($entry_pass->get_text());
      my $local = "";
      $local = trim($entry_local->get_text()), if ($chk_local->get_active());
      
      my $nok = undef;
      if ($sharename=~/\s+/ || $local=~/\s+/) {
        $nok = "A name of a share may not contain spaces or tabs";
      }
      
      if (defined($nok)) { # Error
         show_message_dialog($dialog, "PerlShare - Create Share", 'error', $nok);
         $response = 2;
      } else {
        my $result = $shares->create_share($sharename, $host, $email, $pass, $local);
        if ($result == 0) { # Error
          show_message_dialog($dialog, "PerlShare - Create Share", 'error', $shares->get_message());
          $response = 2;
        } else { # recreate menu
          my $menu = create_menu($shares, $status_icon, $data_queue);
          show_message_dialog($dialog, "PerlShare - Create Share", 'info', "Share $sharename has sucessfully been created");
          sync_now($shares, $sharename, $status_icon, $data_queue);
        }
      }
    }
  }
  
  $dialog->destroy();
}

sub share_collision($) {
  my $shares = shift;
  my $share = shift;
  my $thr=threads->create(sub {
    my $shr = shift;
    my $unison = new Unison();
    $unison->run_gui($shr);
  }, $share);
  $thr->detach();
}

sub sync_now($$) {
  my $shares = shift;
  my $share = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $thr=threads->create(sub {
    my $shr = shift;
    my $unison = new Unison();
    $unison->run($shr, sub { report_cb(@_, $data_queue); }, 1);
  }, $share);
  $thr->detach();
}

sub report_cb($$$$) {
  my $sharename = shift;
  my $state = shift;
  my $code = shift;
  my $data_queue = shift;

  $data_queue->enqueue("$sharename,$state,$code");
}

sub show_message_dialog($$$$) {
#you tell it what to display, and how to display it
#$icon can be one of the following:	a) 'info'
#					b) 'warning'
#					c) 'error'
#					d) 'question'
#$text can be pango markup text, or just plain text, IE the message
  my ($parent,$title, $icon,$text) = @_;
  my $dialog = Gtk2::MessageDialog->new_with_markup ($parent,
  					[qw/modal destroy-with-parent/],
  					$icon,
  					'ok',
  					sprintf "$text");
  
  $dialog->set_title($title);
  $dialog->run;
 	$dialog->destroy;
}



