require 'capistrano'
require 'capistrano/ext/multistage'
require 'capistrano/gitflow_version/natcmp'
require 'stringex'

module Capistrano
  module GitflowVersion
    def self.load_into(capistrano_configuration)
      capistrano_configuration.load do
        before "deploy:update_code", "gitflow_version:calculate_tag"
        before "gitflow_version:calculate_tag", "gitflow_version:verify_up_to_date"

        namespace :gitflow_version do
          def last_tag_matching(pattern)
            matching_tags = `git tag -l '#{pattern}'`.split
            matching_tags.sort! do |a,b|
              String.natcmp(b, a, true)
            end

            last_tag = if matching_tags.length > 0
                         matching_tags[0]
                       else
                         nil
                       end
          end

          def last_staging_tag()
            last_tag_matching('test-*')
          end

          def next_staging_tag
            new_tag_serial = if last_production_tag == next_production_tag
                               Capistrano::CLI.ui.ask("What is the release after #{last_production_tag}? (must be in MAJOR.MINOR.REVISION.BUILD format) ")
                             else
                               if last_staging_tag && last_staging_tag =~ /test-([0-9]+.[0-9]+.[0-9]+.)([0-9]+)/
                                 $1 + ($2.to_i + 1).to_s
                               else
                                 release = Capistrano::CLI.ui.ask("What is the starting release? (must be in MAJOR.MINOR.REVISION.BUILD format) ")
                                 unless release =~ /[0-9]+.[0-9]+.[0-9]+.[0-9]+/
                                   abort "#{release} must be in MAJOR.MINOR.REVISION.BUILD format. example: 0.8.5.0"
                                 end
                                 release
                               end
            end


            "test-#{new_tag_serial}"
          end

          def last_production_tag()
            last_tag_matching('v*')
          end

          def next_production_tag
            last_staging_tag = last_tag_matching("test-*")

            last_staging_tag =~ /^test-(.*)$/
            "v#{$1}"
          end

          def using_git?
            fetch(:scm, :git).to_sym == :git
          end

          task :verify_up_to_date do
            if using_git?
              set :local_branch, `git branch --no-color 2> /dev/null | sed -e '/^[^*]/d'`.gsub(/\* /, '').chomp
              set :local_sha, `git log --pretty=format:%H HEAD -1`.chomp
              set :origin_sha, `git log --pretty=format:%H #{local_branch} -1`
              unless local_sha == origin_sha
                abort """
Your #{local_branch} branch is not up to date with origin/#{local_branch}.
Please make sure you have pulled and pushed all code before deploying:

    git pull origin #{local_branch}
    #run tests, etc
    git push origin #{local_branch}

    """
              end
            end
          end

          desc "Calculate the tag to deploy"
          task :calculate_tag do
            if using_git?
              # make sure we have any other deployment tags that have been pushed by others so our auto-increment code doesn't create conflicting tags
              `git fetch`

              send "tag_#{stage}" if respond_to?(stage)

              system "git push --tags origin #{local_branch}"
              if $? != 0
                abort "git push failed"
              end
            end
          end

          desc "Show log between most recent staging tag (or given tag=XXX) and last production release."
          task :commit_log do
            from_tag = if stage == :production
                         last_production_tag
                       elsif stage == :staging
                         last_staging_tag
                       else
                         abort "Unsupported stage #{stage}"
                       end

            # no idea how to properly test for an optional cap argument a la '-s tag=x'
            to_tag = capistrano_configuration[:tag]
            to_tag ||= begin
                         puts "Calculating 'end' tag for :commit_log for '#{stage}'"
                         to_tag = if stage == :production
                                    last_staging_tag
                                  elsif stage == :staging
                                    'master'
                                  else
                                    abort "Unsupported stage #{stage}"
                                  end
                       end


            command = if `git config remote.origin.url` =~ /git@github.com:(.*)\/(.*).git/
                        "open https://github.com/#{$1}/#{$2}/compare/#{from_tag}...#{to_tag || 'master'}"
                      else
                        log_subcommand = if ENV['git_log_command'] && ENV['git_log_command'].strip != ''
                                           ENV['git_log_command']
                                         else
                                           'log'
                                         end
                        "git #{log_subcommand} #{from_tag}..#{to_tag}"
                      end
            puts command
            system command
          end

          desc "Mark the current code as a staging/qa release"
          task :tag_staging do
            current_sha = `git log --pretty=format:%H HEAD -1`
            last_staging_tag_sha = if last_staging_tag
                                     `git log --pretty=format:%H #{last_staging_tag} -1`
                                   end

            if last_staging_tag_sha == current_sha
              puts "Not re-tagging staging because the most recent tag (#{last_staging_tag}) already points to current head"
              new_staging_tag = last_staging_tag
            else
              new_staging_tag = next_staging_tag
              puts "Tagging current branch for deployment to staging as '#{new_staging_tag}'"
              system "git tag -a -m 'tagging current code for deployment to staging' #{new_staging_tag}"
            end

            set :branch, new_staging_tag
          end

          desc "Push the last staging tag to production."
          task :tag_production do
            promote_to_production_tag = last_staging_tag

            unless promote_to_production_tag && promote_to_production_tag =~ /test-.*/
              abort "Couldn't find a staging tag to deploy; use '-s tag=test-MAJOR.MINOR.REVISION.BUILD'"
            end
            unless last_tag_matching(promote_to_production_tag)
              abort "Staging tag #{promote_to_production_tag} does not exist."
            end

            promote_to_production_tag =~ /^test-(.*)$/
            new_production_tag = "v#{$1}"

            if new_production_tag == last_production_tag
              puts "using current production tag '#{new_production_tag}'"
            else
              puts "promoting staging tag #{promote_to_production_tag} to production as '#{new_production_tag}'"
              system "git tag -a -m 'tagging current code for deployment to production' #{new_production_tag} #{promote_to_production_tag}"
            end

            set :branch, new_production_tag
          end
        end

        namespace :deploy do
          namespace :pending do
            task :compare do
              gitflow_version.commit_log
            end
          end
        end

      end

    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::GitflowVersion.load_into(Capistrano::Configuration.instance)
end
