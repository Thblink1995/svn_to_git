# svn_to_git_overwrite

## Summary

SH script allowing to clone a SVN repository and migrate it to a git repository, keeping all data such as tags, branches, commit logs etc. Update previous migration but erases git changes that were done since the last migration.

## Requirements

The script will work only if SVN repository follows classic architecture (trunk being the main branch).
Linux or MacOS.

# svn_to_git_update

## Summary

SH script allowing to clone a SVN repository, compare it to a Gitlab repository, and create merge requests towards branches that were modified since last script execution.
Basically, updates a previous svn_to_git migration.

## Requirements

Works only if SVN repository follows classic SVN architecture (trunk being the main branch).
Linux or MacOS.
Requires an online git repository, more specifically a Gitlab one, but that can be changed easily to a github one or else.
