# ~/.bash_aliases: Included by ~/.bashrc

# Ruby tooling aliases
alias reek="bundle exec reek"
alias {rs,rspec}="bundle exec rspec"
alias rubocop="bundle exec rubocop"

# Shellcheck alias
alias sc="shellcheck"

# Sublime alias
alias {subli,sublm,sublim,sublime}="subl"

# Sudo alias
# If the last character of the alias value is a space or tab character,
# then the next command word following the alias is also checked for alias expansion.
# i.e 'sudo aliasname' should now work
alias sudo="sudo "
