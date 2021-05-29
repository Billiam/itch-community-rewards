require "dry/cli"
require "tty-prompt"
require "tty-table"
require "itch_client"
require "bigdecimal"
require "pastel"

module ItchRewards
  class CLI
    module AuthOptions
      def self.included(base)
        base.class_eval do
          option :username, desc: "Itch username", aliases: ["u"]
          option :password, desc: "Itch password", aliases: ["p"]
          option :cookie_path, desc: "Path to cookies file for future logins", default: ".itch-cookies.yml"
          option :cookies, desc: "Enable cookie storage", type: :boolean, default: true
          option :interactive, type: :boolean, desc: "Enable interactive prompts", default: true
        end
      end
    end

    module Helper
      def cli
        @cli ||= begin
          TTY::Prompt.new
        end
      end

      def color
        @pastel ||= Pastel.new
      end

      def authenticated_client(options)
        @authenticated_client ||= begin
          interactive = options[:interactive]

          username = options[:username] || -> { interactive ? cli.ask("Itch.io username:", required: true) : (cli.error("Username required but not provided"); exit 1) }
          password = options[:password] || -> { interactive ? cli.mask("Itch.io password:", required: true) :  (cli.error("Password required but not provided"); exit 1) }
          totp = -> { interactive ? cli.mask("Enter your 2FA code", required: true) : (cli.error("Cannot enter totp code in non-interactive mode"); exit 1) }

          cookie_path = options[:cookies] ? options[:cookie_path] : nil
          
          client = Itch.new(username: username, password: password, cookie_path: cookie_path)
          client.totp = totp
          
          client.login && client
        rescue Itch::AuthError => e
          cli.error(e.message)
          nil
        end
      end

      def authenticated_client!(options)
        authenticated_client(options) || exit(1)
      end

      def objects_to_table(objects)
        objects = Array(objects)
        return nil if objects.none?
        if objects.first.is_a? Hash
          headers = objects.first.keys.sort          
          data = objects.map {|v| v.values_at(*headers) }
          headers = headers.map(&:upcase)
        else
          fields = objects.first.instance_variables.sort
          data = objects.map do |object|
            fields.map {|k| object.instance_variable_get(k) }
          end
          headers = fields.map {|f| f.to_s[1..].upcase }
        end

        TTY::Table.new(headers, data)
      end

      def render_table(table)
        return "No data" unless table

        table.render(:unicode, multiline: true, padding: [0,1], resize: false, border: { style: :green })
      end

      def show_rewards(game)
        cli.say "Rewards for #{game.name} (id: #{game.id})"
        table = objects_to_table(game.rewards.list)
        cli.say render_table(table)
      end
    end

    module Commands
      extend Dry::CLI::Registry

      class Version < Dry::CLI::Command
        include Helper

        desc "Print version"

        def call(*)
          cli.say "ItchRewards #{ItchRewards::VERSION} (ItchClient #{Itch::VERSION})"
        end
      end

      class Setup < Dry::CLI::Command
        include Helper
        include AuthOptions
        @options = @options.reject {|opt| [:cookies, :interactive].include? opt.name }

        def write_config(path, options)
          require 'erb'
          client = authenticated_client!(options)
          
          games = client.game_map.map.values
          template = File.read(File.join(__dir__, 'templates/reward_config.yml.erb'))

          File.write(path, ERB.new(template, trim_mode: '-').result(binding))
        end

        desc "Save cookies for itch.io and create reward config example file"
        def call(**options)
          options[:cookies] ||= cli.ask("Where would you like to store your login cookies?  ", default: ".itch-cookies.yml")
          options[:interactive] = true

          if authenticated_client(options)
            cli.say "Saved cookies to #{options[:cookie_path]}"
          else
            cli.say "Login failed, cookies not saved"
          end

          config_path = "itch-reward-config.yml"

          if !File.exist? config_path
            result = cli.yes?("Config file #{config_path} does not exist, would you like to create it?")

            if result
              write_config(config_path, options)
              cli.say "Config file written to #{config_path}"
            end
          else
            cli.warn "Config file #{config_path} already exists, skipping..."
          end
        end
      end

      module Games
        class List < Dry::CLI::Command
          include AuthOptions
          include Helper
  
          desc "List all games"
          def call(**options)
            client = authenticated_client!(options)
            table = objects_to_table(client.game_map.map.values)
            
            cli.say "Games"
            cli.say render_table(table)
          end
        end
      end

      module Rewards
        class List < Dry::CLI::Command
          include AuthOptions
          include Helper
  
          desc "List all rewards for a game"

          option :id, type: :string, desc: "Game ID"
          option :name, type: :string, desc: "Game name"

          example [
            "--id 123456     # List rewards for game with ID 123456",
            "--name MyGame   # List rewards for game with name MyGame"
          ]
          def call(**options)
            if options[:id].nil? && options[:name].nil?
              cli.error "Game ID or game name argument is required"
              exit 1
            end

            client = authenticated_client!(options)
            game = options[:id] ? client.game(options[:id]) : client.game(name: options[:name])

            show_rewards(game)
          end
        end

        class Update < Dry::CLI::Command
          include AuthOptions
          include Helper
  
          desc "Update a reward"

          example [
            "123456 78910 --quantity 5            # Set the reward count to 5 for reward ID 78910 in game ID 123456",
            "123456 78910 --price 5.00 --archived # Set reward price to 5.00 and archive it"
          ]
          
          argument :game_id, required: true, desc: "Game with the reward to edit"
          argument :reward_id, type: :integer, required: true, desc: "Reward ID to update"

          option :quantity, desc: "Reward quantity (total, including redeemed)"
          option :title, type: :string, desc: "Reward title"
          option :archived, type: :boolean, desc: "Reward archived status"
          option :description, type: :string, desc: "Reward description"
          option :price, type: :string, desc: "Reward price without currency (ex: 15.99)"
          
          def call(game_id:, reward_id:, **options)
            client = authenticated_client!(options)
            game = client.game(game_id)
            rewards = game.rewards
          
            reward_id = reward_id.to_i
            reward_list = rewards.list

            reward = reward_list.find {|reward| reward.id == reward_id }

            unless reward
              cli.error "Could not find reward with id: #{reward_id} for game #{game.name} (#{game.id})"
              exit 1
            end
            
            unless options[:archived].nil?
              reward.archived = options[:archived]
            end

            %i(amount description price title).each do |field|
              if options[field]
                reward.public_send("#{field}=", options[field])
              end
            end

            rewards.save reward_list
            
            show_rewards(game)
          end
        end

        class Automate < Dry::CLI::Command
          include Helper
          include AuthOptions

          def load_config(path)
            YAML.load_file(path)
          rescue YAML::ParseError => e
            cli.error("Config file (#{path}) is not valid yaml")
            exit 1
          end

          desc "Update reward quantity and description from configuration file"

          option :config, required: true, desc: "Path to config file", default: "itch-reward-config.yml"
          option :save, type: :boolean, desc: "Saves changes when enabled. Otherwise, dry-run and show result", default: false

          def call(**options)
            client = authenticated_client!(options)

            if !File.exist? options[:config]
              cli.error("Config file #{options[:config]} does not exist")
              exit 1
            end

            config = load_config(options[:config])
            unless config["games"].is_a? Hash
              cli.error("No games configured for rewards updates in config file")
              exit 1
            end
            
            unless options[:save]
              cli.warn "Dry run, results will not not saved"
            end

            purchases_by_game = client.purchases.history.each.group_by {|row| row['object_name'] }.to_h

            config["games"].each do |name, data|
              name = name.chomp

              next unless data["reward_by_tip"] > 0 || data["reward_by_purchase"] > 0 || data["minimum_available"] > 0
              game = client.game(data["id"])
              rewards = game.rewards.list
            
              reward = rewards.find {|r| r.id == data["reward_id"]}
              unless reward
                cli.warn "Could not find reward #{data["reward_id"]} for game #{name}, skipping..."
                next
              end

              tip_modifier = data["reward_by_tip"].to_f
              purchase_modifier = data["reward_by_purchase"].to_f
              minimum = data["minimum_available"].to_i
              template = data["reward_description_template"]

              new_description = reward.description              
              new_amount = Array(purchases_by_game[name]).inject(data["reward_offset"]) do |sum, purchase|
                price = purchase["product_price"].to_i
                tip = (purchase["tip"].to_f * 100).to_i

                next sum unless price > 0
                
                sum += (tip.fdiv(price)) * tip_modifier
                sum += purchase_modifier

                sum
              end
              new_amount = [new_amount, reward.claimed + minimum].max if minimum > 0

              if template && !template.empty?
                new_description = template.gsub(/{ *(quantity|remaining_percent|remaining_percent_integer) *}/, "{\\1}")
                  .gsub(/{ *(quantity|remaining_percent|remaining_percent_integer) *}/,
                    "{quantity}" => new_amount.floor,
                    "{remaining_percent}" => ((new_amount % 1) * 100).floor(1),
                    "{remaining_percent_integer}" => ((new_amount % 1) * 100).floor
                  )
              end
              
              if new_amount.to_i != reward.amount
                cli.say "Changing #{name} reward #{reward.id} quantity from #{color.green.bold(reward.amount.to_s)} to #{color.yellow.bold(new_amount.to_i)}"
              end
                          
              if new_description != reward.description
                cli.say "Changing #{name} reward #{reward.id} description to:\n#{color.yellow.bold(new_description)}"
              end

              if options[:save]
                reward.description = new_description
                reward.amount = new_amount.to_i

                game.rewards.save rewards
              end
            end
          end
        end
      end

      register "version", Version, aliases: ["v", "-v", "--version"]
      register "setup", Setup
      register "list", Rewards::List
      register "list-games", Games::List
      register "update", Rewards::Update
      register "recalculate", Rewards::Automate
    end
  end

  class App < Dry::CLI
    def usage_prefix
      err.puts "Usage: #{ProgramName.call()} COMMAND [options]\n\n"
    end

    def usage_suffix
      err.puts "\nGlobal options:\n  -h            # Show help for command"
    end

    def usage(result)
      usage_prefix
      err.puts Usage.call(result)
      usage_suffix
      exit(1)
    end
  end
end

ItchRewards::App.new(ItchRewards::CLI::Commands).call
