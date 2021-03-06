#!/bin/perl

# the aim of the script history2gitcommands.pl is to migrate a project managed in synergy toward a git repository
# it assumes dump_ccm.sh has already be runned to extract 
# the parameters are:
# - repo_directory: the prefix used for the creation of two directories
#    - <repo_directory>_repo that will contain the git repository. It should be created before running this script if we need a .gitignore
#    - <repo_directory>_src that will be used for extraction
# - ccm: the constant string "ccm"
# - subadds: the string "$PWD/subadd.sh  <absolute_path_to_dump>"
#      this is used to launch script subadd.sh that takes a single parameter: the repo_directory
# - folderinside: specific directory (in source of a ccm cfs) where directly get the files
#
# the input of this script is the history of a project
# the output of this script is a bash script that contains all the commands to be executed


$folder = shift;
$folder = "repo" if (!$folder);
$folder_repo = $folder."_repo";
$folder_src = $folder."_src";
$ccm_cmd = shift;
$ccm_cmd = "ccm" if (!$ccm_cmd);
$subadds = shift;
$folderinside = shift;
$folderinside = "" if (!$folderinside);

# parse stdin (the history of a project)
use File::Basename;
$_dir_ = dirname(__FILE__);
require $_dir_."/history.pm";

# Replace all the # and : characters in the objectname by underscores. This sanitization ensures
# it can be used as tag name.
sub key2tagname {
  my ($key) = @_;
  $key =~ s/[#:]/_/g;
  return $key;
}

sub followtree {
  my ($key, $tirets) = @_;
  my $status = `ccm attr -s status -p $key`;
  chomp ($status);
  # Migrate only "released" or "integrate" projects
  if (($status ne "released") && ($status ne "integrate")) {
     return;
  }
  my $cauthor, $cdate, $ccomment, $cpredecessor, $cbranch;
  $cbranch = key2tagname($key);
  $cpredecessor = key2tagname($objects{$key}{"Predecessors"}[0]);
  $cpredecessor = "initial_commit" unless($cpredecessor);
  $owner = $objects{$key}{"Owner"};
  $cauthor = "$owner <" . $owner . "\@eurocontrol.int>";
  $cdate = $objects{$key}{"Created"};
  $ccomment = "Project $key - ".join(" ", @{$objects{$key}{"Comment"}})." - tasks: ".$objects{$key}{"Task"}." ";
  # reset the branch master to point to the commit of the previous version of project
  print "git checkout -b master tags/$cpredecessor\n";
  print "cd ..\n";
  # empty the directory that will be used for synergy extraction
  print "rm -rf $folder_src\n";
  print "mkdir -p $folder_src\n";
  # synergy recursive copy of a project to file system (in directory $folder_src)
  # before execution of this script the following settings shall be adjust on work area:
  #  - Place work area relative to parent projects's
  #  - File Options: copies
  print "$ccm_cmd cfs -r \"$key\" -p $folder_src\n";
  print "cd $folder_src\n";
  # for each link toward a directory in $folder_src, replace it be a copy of the directory tree pointed by the link
  print 'find . -type l | while read link ; do if test -d "$link"; then source=$(readlink "$link"); if test -d "$source" ; then rm "$link" ; cd $(dirname $link) ; rsync -a "$source" . ; cd - ; fi ; fi ; done'."\n";
  print "cd ..\n";
  # empty the working tree (removes everything except .git directory and .gitignore file)
  print "rm -rf $folder_repo/*\n";
  # copy from the directory where the synergy extraction has occurred toward git working tree
  print "rsync -a $folder_src/$folderinside/ $folder_repo\n";
  print "cd $folder_repo\n";
  # create an empty file named .empty in all directories that are empty so that they can be stored in git
  print "find . -type d -empty -exec touch '{}'/.empty ';'\n";
  # optionally, call the script $subadds. This script is in charge of creating intermediate commits related to synergy's tasks
  print "$subadds \n" if ($subadds);
  # put on the stage all the removed, modified or created files of the working tree
  print "git add -A .\n";
  # commit even if the tree is identical to the tree of previous commit
  print "GIT_COMMITTER_DATE=\"$cdate\" git commit --allow-empty --author \"$cauthor\" --date \"$cdate\" -m \"$ccomment (imported via git2synergy)\"\n";
  # associates as tag of this commit, the objectname (sanitized) of the project's version
  print "git tag $cbranch\n";
  # progression information of stderr
  print STDERR "$tirets $key\n";
  # recursive call for each successor of current version of project
  foreach $successor (@{$objects{$key}{"Successors"}}) {
    followtree($successor, $tirets.'-');
  }
}
# initialize the git repository
print("mkdir -p $folder\n");
print("cd $folder\n");
print("mkdir -p $folder_repo\n");
print("cd $folder_repo\n");
print("rm -rf .git *\n");
print("git init\n");
print("printf \"# $title \\n\\nrepository generated automaticaly\\n\" > README.md\n");
print("git add README.md\n");
# keep .gitignore file if exist in parent directory
print ("if [ -f '../.gitignore' ];then\ncp ../.gitignore .\nfi\n");
# or if exist inside directory $folder_repo
print ("if [ -f '.gitignore' ];then\ngit add .gitignore\nfi\n");
print("GIT_COMMITTER_DATE=\"Mon Jan  1 00:00:00 CET 1990\" git commit --date=\"Mon Jan  1 00:00:00 CET 1990\" --author=\"synergy2git <contact@24eme.fr>\" -m \"initial commit\"\n");
print("git tag initial_commit\n");
# for each version of the project that have no ancestor
foreach $first (@firsts) {
  followtree($first, '-');
}
print ("git-big-picture -o ../repo.png -a .\n");
print ("cd ..\n");
