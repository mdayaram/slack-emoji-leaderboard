Slack Emoji Leaderboard
=======================

Who has uploaded the most emoji's to slack this week? Now you can finally know!

## Requirements

Ruby 3.3.6

For some reason, it seemed to fail in Ruby 3.1.6, and I didn't bother trying to figure out
why or what other versions it fails at, so for a guaranteed working experience, just use
3.3.6

## Setup

We use environment variables to access the tokens and cookies needed to query
Slack's API. Copy the sample file over to a `.env` file:

```
cp env.sample .env
```

And fill in the two values with the appropriate token and cookie that you get from
Slack. This is a bit hacky because I wanted to avoid having to make a specific API
key or Slack App or Robot, so I just get these values from the Chrome inspector when
browsing Slack's emoji page.  Use the following steps to get them yourself:

1) In Slack, go to the main Slack menu -> Customize Workplace
2) On the given page, open up developer tools and look at the
   network requests. Specifically inspect the `adminList` request.
3) From there, you can grab the `token` value from the request body and
   the value of the cookie named `d`.
4) Set those values in your `.env` file.

Then make sure to bundle install and you're ready to go!

```
bundle install
```

## Run

```
./main.rb --help
Usage: ./main.rb [--weeks 1 --top 5]
        --weeks NUM                  How many weeks ago to check for emoji uploads. Defaults to all time.
        --years NUM                  How many years ago to check for emoji uploads. Defaults to all time.
        --top NUM                    Show the top NUM uploaders, defaults to displaying all.
```

Example run:

```
./main.rb --weeks 5 --top 3
Reading emojis from cache...

Showing the top 3 emoji uploaders since 2024-11-15 15:42:40 -0800:

1) @Sangoro: 7
2) @Luffytaro: 4
3) @Zorojuro: 3

:99: :chill-guy: :copy_that: :done2: :makessense: :outofoffice: :stressed: :bufo-offers-a-report-in-these-trying-times: :bufo-offers-perrot: :bufo-offers-reports: :lucas-lobster: :frankie-dog: :george-dog: :nala-dog: 
```
