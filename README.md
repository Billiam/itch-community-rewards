# itch-rewards

Commandline tool to update game rewards on Itch.io, and automatically update reward counts and descriptions based on sales.

## Installation

    $ gem install itch_rewards

## Usage

```shell
Usage: itch-rewards COMMAND [options]

Commands:
  itch-rewards list                                        # List all rewards for a game
  itch-rewards list-games                                  # List all games
  itch-rewards recalculate                                 # Update reward quantity and description from configuration file
  itch-rewards setup                                       # Save cookies for itch.io and create reward config example file
  itch-rewards update GAME_ID REWARD_ID                    # Update a reward
  itch-rewards version                                     # Print version
```

### Authenticating

First, enable two-factor authentication for your itch.io account, if you haven't already. This prevents captcha prompts during login, which `itch-rewards` doesn't handle.

Then, run:

```shell
$ itch-rewards setup
```

You'll be prompted for your username, password, two-factor code, and a path to save a cookie file. Your credentials will not be saved, but the cookie will be used for subsequent logins (until the cookie expires).

You can use `itch-rewards` for multiple accounts by specifying a different cookie file path for each account:

```shell
$ itch-rewards setup --cookie-path my_first_account.yml
# ...
$ itch-rewards setup --cookie-path my_second_account.yml
# ...
$ itch-rewards list-games --cookie-path my_first_account.yml
```

You'll also be prompted to create an (optional) configuration file that can be used when automatically updating itch reward quantities and descriptions.

While logging in via cookies is easier (and required for non-interactive login, ex: for cron tasks), all commands also accept the following options.

```shell
--username=VALUE, -u VALUE        # Itch username
--password=VALUE, -p VALUE        # Itch password
--cookie-path=VALUE               # Path to cookies file for future logins, default: ".itch-cookies.yml"
--[no-]cookies                    # Enable cookie storage, default: true
--[no-]interactive                # Enable interactive prompts, default: true
--help, -h                        # Print help
```

### List games

Return a list of game names and IDs. Useful for other commands that use game ID, or when creating a [reward configuration file](#reward-configuration).


```shell
Usage:
  itch-rewards list-games

Description:
  List all games
```


### List rewards

Show reward information for a single game.

Accepts either a game name, or game ID.
```shell
Usage:
  itch-rewards list

Description:
  List all rewards for a game

Options:
  --id=VALUE                        # Game ID
  --name=VALUE                      # Game name

Examples:
  itch-rewards list --id 123456     # List rewards for game with ID 123456
  itch-rewards list --name MyGame   # List rewards for game with name MyGame
```

### Update a reward

Update a single reward for a game. Quantity, title, description, price and archive status can be changed.

```shell
Command:
  itch-rewards update

Usage:
  itch-rewards update GAME_ID REWARD_ID

Description:
  Update a reward

Arguments:
  GAME_ID                           # REQUIRED Game with the reward to edit
  REWARD_ID                         # REQUIRED Reward ID to update

Options:
  --quantity=VALUE                  # Reward quantity (total, including redeemed)
  --title=VALUE                     # Reward title
  --[no-]archived                   # Reward archived status
  --description=VALUE               # Reward description
  --price=VALUE                     # Reward price without currency (ex: 15.99)

Examples:
  itch-rewards update 123456 78910 --quantity 5            # Set the reward count to 5 for reward ID 78910 in game ID 123456
  itch-rewards update 123456 78910 --price 5.00 --archived # Set reward price to 5.00 and archive it
```

### Automated reward updates

If you wish to update a reward description, or available quantity based on purchases or tips.

```shell
Usage:
  itch-rewards recalculate

Description:
  Update reward quantity and description from configuration file

Options:
  --config=VALUE                    # Path to config file, default: "itch-reward-config.yml"
  --[no-]save                       # Saves changes when enabled. Otherwise, dry-run and show result, default: false
```


#### Reward configuration

Automatic reward updates require a reward configuration file. You can create an annotated file, prepopulated with all of your itch games by using the [setup command](#authenticating).

A reward configuration looks like this

```yml
---
games:
  MyGame:
    id: 123456
    reward_id: 789012
    reward_by_purchase: 0
    reward_by_tip: 0.0
    reward_offset: 0
    minimum_available: 0
    reward_description_template:

  MyOtherGame:
    ...
```

#### Some example reward scenarios

> I want every purchase to add one community copy

```yml
MyGame:
  id: 123456
  reward_id: 789012
  reward_by_purchase: 1
  reward_by_tip: 0.0
  reward_offset: 0
  minimum_available: 0
```


> I want every two purchases to add one community copy
```yml
MyGame:
  id: 123456
  reward_id: 789012
  reward_by_purchase: 0.5
  reward_by_tip: 0.0
  reward_offset: 0
  minimum_available: 0
```

> I want tips over the purchase price to add proportional community copies


```yml
MyGame:
  id: 123456
  reward_id: 789012
  reward_by_purchase: 0
  reward_by_tip: 1.0
  reward_offset: 0
  minimum_available: 0
```

For example: a $5 tip, on a $10 game will contribute 0.5 copies to the reward pool when `reward_by_tip` is `1`.

The formula for this is: `(tip_amount / game_price) * reward_by_tip`


> I want five community copies to always be available

```yml
MyGame:
  id: 123456
  reward_id: 789012
  reward_by_purchase: 0
  reward_by_tip: 0.0
  reward_offset: 0
  minimum_available: 5
```

#### Updating reward description

If present, the `reward_description_template` configuration value can be used to change the description of your reward with information about the reward itself.

For instance: 

```yml
reward_description_template: <p>Rewards added: { amount }</p>
```

The above will change the reward description to "Rewards added: 10".
The following placehoder values are available:
  * `{ amount }`: The total number of reward copies in the pool, including redeemed rewards.
  * `{ remaining_percent }`: A number between 0.0 and 100.0, indicating the percentage until the next reward
  * `{ remaining_percent_integer }`: A number between 0 and 100. As above (but with no decimal value included).
