#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""Simple Bot to reply to Telegram messages.

This program is dedicated to the public domain under the CC0 license.

This Bot uses the Updater class to handle the bot.

First, a few handler functions are defined. Then, those functions are passed to
the Dispatcher and registered at their respective places.
Then, the bot is started and runs until we press Ctrl-C on the command line.

Usage:
Basic Echobot example, repeats messages.
Press Ctrl-C on the command line or send a signal to the process to stop the
bot.
"""

from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import logging
import configparser
from crontab import CronTab
from sh import tail
import datetime

# Enable logging
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                    level=logging.INFO)

logger = logging.getLogger(__name__)


# Define a few command handlers. These usually take the two arguments bot and
# update. Error handlers also receive the raised TelegramError object in error.
def start(bot, update):
    """Send a message when the command /start is issued."""

    my_cron = CronTab(user='feyruz')
    already_running = False
    for job in my_cron:
        if job.comment == 'knight-rider':
            already_running = True
    if (already_running) :
        update.message.reply_text('I am already active and hunting, mate! (btw you could check my logs to see my state...)')
    else:
        job = my_cron.new(command='source /home/feyruz/.bashrc; /home/feyruz/perl5/perlbrew/perls/perl-5.20.3/bin/perl /home/feyruz/sandbox/RideAway-AutoResponder/script/ra_autorespond.pl >> /home/feyruz/sandbox/RideAway-AutoResponder/logs/crontab.out 2>&1', comment='knight-rider')
#        cron_minutes_str = get_cron_minutes()
        cron_minutes_str = '0,15,30,45 * * * *'
        job.setall(cron_minutes_str)
        update.message.reply_text('I will start hunting for rides now: Crontab - ' + cron_minutes_str)
        my_cron.write()

def stop(bot, update):
    """Send a message when the command /stop is issued."""

    my_cron = CronTab(user='feyruz')
    was_running = False
    for job in my_cron:
        if job.comment == 'knight-rider':
            was_running = True
            my_cron.remove(job)
            my_cron.write()

    if (was_running):
        update.message.reply_text('Okay, I will stop hunting.')
    else:
        update.message.reply_text('Stop what? You had already stopped me!')

def status(bot, update):

    my_cron = CronTab(user='feyruz')
    already_running = False
    for job in my_cron:
        if job.comment == 'knight-rider':
            already_running = True
    if (already_running) :
        update.message.reply_text('Running')
    else:
        update.message.reply_text('Stopped')

def logs(bot, update):
    debug_arr = []
    imap_arr  = []
    app_arr   = []
    for line in tail("-n 1", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/app.verbose.log", _iter=False):
        debug_arr.append(line)
    for line in tail("-n 10", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/app.log", _iter=False):
        app_arr.append(line)

    for line in tail("-n 3", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/imap.live.log", _iter=False):
        line = line.rstrip()
        imap_arr.append(line[0:30] + '\n')

    update.message.reply_text('******* DEBUG ********\n' + ''.join(debug_arr) + '\n******* APP ********\n' + ''.join(app_arr) + '\n******* IMAP ********\n' +  ''.join(imap_arr))
   # update.message.reply_text('******* DEBUG ********\n' + ''.join(debug_arr) + '\n******* IMAP ********\n' +  ''.join(imap_arr))

def echo(bot, update):
    """Echo the user message."""
    update.message.reply_text(update.message.text)

def get_cron_minutes():
    now = datetime.datetime.now()
    curr_minute = now.minute + 1
    interval = 15
    minutes = []

    for i in (range(0,4)):
        minute = (curr_minute + i * interval) % 60
        minutes.append(str(minute))
    return ','.join(minutes) + ' * * * *'

def error(bot, update, error):
    """Log Errors caused by Updates."""
    logger.warning('Update "%s" caused error "%s"', update, error)


def main():

    config = configparser.ConfigParser()
    config.read('/home/feyruz/sandbox/RideAway-AutoResponder/config/config.live.ini')
    token = config['telegram']['token']

    """Start the bot."""
    # Create the EventHandler and pass it your bot's token.
    updater = Updater(token)

    # Get the dispatcher to register handlers
    dp = updater.dispatcher

    # on different commands - answer in Telegram
    dp.add_handler(CommandHandler("start", start))
#    dp.add_handler(CommandHandler("help", help))
    dp.add_handler(CommandHandler("stop", stop))
    dp.add_handler(CommandHandler("logs", logs))
    dp.add_handler(CommandHandler("status", status))

    # on noncommand i.e message - echo the message on Telegram
    dp.add_handler(MessageHandler(Filters.text, echo))

    # log all errors
    dp.add_error_handler(error)

    # Start the Bot
    updater.start_polling()

    # Run the bot until you press Ctrl-C or the process receives SIGINT,
    # SIGTERM or SIGABRT. This should be used most of the time, since
    # start_polling() is non-blocking and will stop the bot gracefully.
    updater.idle()


if __name__ == '__main__':
    main()
