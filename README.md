Twitter Inactive Followers
==========================

I've made this script to try to find how many of the followers I have on twitter are inactive accounts. I think there are already services which does this and my approach to mark an account as inactive is naive, just coded this because I was bored.

Requeriments
------------

* Ruby 1.9.x (I used 1.9.2).
* Twitter gem

How to use it
-------------

    ruby inactive-followers <scree_name> <inactive_days> [-n]

The script has two phases, first it gets the needed data from Twitter:

* get the user followers
* for each follower, get last tweet and user info

All the data is saved locally. Twitter API has a limit of 150 requests per hour, the script does not do any throttling, it consumes all the requests it can, then it sleeps until it can continue.

Then it uses the data to check which follower is inactive:

* each follower has a score, it starts at 0
* if certain criteria are met, increase the score
* list all users whose score is above certain threshold

This approach is naive and when I've tested with my own account I've seen some false positives.

The `-n` parameter is used when you want to avoid the first phase and only used the locally saved data.
The `inactive_days` parameter is used as one of the criteria used of the second phase.

License
-------

This script is licensed under the BOLA license
Where this BOLA license comes from? Read about it on [Alberto's site|http://blitiri.com.ar/p/bola/]

