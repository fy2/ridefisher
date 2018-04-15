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
import subprocess

# Enable logging
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                    level=logging.INFO)

logger = logging.getLogger(__name__)


# Define a few command handlers. These usually take the two arguments bot and
# update. Error handlers also receive the raised TelegramError object in error.
def start(bot, update):
    """Send a message when the command /start is issued."""

    config = configparser.ConfigParser()
    cfile = '/home/feyruz/sandbox/RideAway-AutoResponder/config/config.live.ini'
    config.read(cfile)
    config['ride']['persist'] = '1'
    with open(cfile, 'w') as configfile:
        config.write(configfile)

    my_cron = CronTab(user='feyruz')
    already_running = False
    for job in my_cron:
        if job.comment == 'knight-rider':
            already_running = True
    if (already_running) :
        update.message.reply_text('I am already active and hunting, mate! (btw you could check my logs to see my state...)')
    else:
        job = my_cron.new(command='PERL5LIB=/home/feyruz/perl5/lib/perl5:/home/feyruz/sandbox/RideAway-AutoResponder/lib /usr/bin/perl /home/feyruz/sandbox/RideAway-AutoResponder/script/ra_autorespond.pl >> /home/feyruz/sandbox/RideAway-AutoResponder/logs/crontab.out 2>&1', comment='knight-rider')
        job.setall( '*/6 * * * *')
        job2 = my_cron.new(command='PERL5LIB=/home/feyruz/perl5/lib/perl5:/home/feyruz/sandbox/RideAway-AutoResponder/lib /usr/bin/perl /home/feyruz/sandbox/RideAway-AutoResponder/script/ra_persist.pl >> /home/feyruz/sandbox/RideAway-AutoResponder/logs/crontab.out 2>&1', comment='persist')
        job2.setall( '*/1 * * * *')

        my_cron.write()
        update.message.reply_text('Okay. I have started. I am Persistent.')

def persistoff(bot, update):
    my_cron = CronTab(user='feyruz')
    for job in my_cron:
        if job.comment == 'persist':
            my_cron.remove(job)
            my_cron.write()
    config = configparser.ConfigParser()
    cfile = '/home/feyruz/sandbox/RideAway-AutoResponder/config/config.live.ini'
    config.read(cfile)
    config['ride']['persist'] = '0'
    with open(cfile, 'w') as configfile:
        config.write(configfile)

    update.message.reply_text('Persistent Mode: 0')

def stop(bot, update):
    """Send a message when the command /stop is issued."""

    my_cron = CronTab(user='feyruz')
    was_running = False
    for job in my_cron:
        if (job.comment == 'knight-rider') or (job.comment == 'persist'):
            my_cron.remove(job)
            my_cron.write()
    update.message.reply_text('No more hunting')

def status(bot, update):

    my_cron = CronTab(user='feyruz')
    kitt_running = False
    persist_running = False
    for job in my_cron:
        if job.comment == 'knight-rider':
            kitt_running = True
        if job.comment == 'persist':
            persist_running = True

    update.message.reply_text('Kitt running - %s' % (kitt_running) )
    update.message.reply_text('Persistent - %s' % (persist_running) )

def logs(bot, update):
    debug_arr = []
    imap_arr  = []
    app_arr   = []
    for line in tail("-n 1", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/app.verbose.log", _iter=False):
        debug_arr.append(line)
    for line in tail("-n 3", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/app.log", _iter=False):
        app_arr.append(line)
    for line in tail("-n 3", "/home/feyruz/sandbox/RideAway-AutoResponder/logs/imap.live.log", _iter=False):
        line = line.rstrip()
        imap_arr.append(line[0:30] + '\n')
    update.message.reply_text('******* APP ********\n' + ''.join(app_arr) + '\n******* DEBUG ********\n' + ''.join(debug_arr) + '\n******* IMAP ********\n' +  ''.join(imap_arr))

def uptime(bot, update):
    # https://stackoverflow.com/questions/15374211/why-does-popen-communicate-return-bhi-n-instead-of-hi
    out = subprocess.check_output(["uptime"]).decode('ascii').rstrip()
    update.message.reply_text(out)

def unsinn(bot, update):
    # https://stackoverflow.com/questions/15374211/why-does-popen-communicate-return-bhi-n-instead-of-hi
    german =  [ '/usr/share/games/fortunes/de/' + i for i in ['letzteworte', 'witze', 'stilblueten', 'sicherheitshinweise', 'wusstensie']]
    out = subprocess.check_output( ["/usr/games/fortune", "/usr/share/games/fortunes/riddles"] + german  ).decode('utf-8').rstrip()
    update.message.reply_text(out)

def echo(bot, update):
    """Echo the user message."""
    update.message.reply_text(update.message.text)

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
    dp.add_handler(CommandHandler("persistoff", persistoff))
    dp.add_handler(CommandHandler("logs", logs))
    dp.add_handler(CommandHandler("status", status))
    dp.add_handler(CommandHandler("uptime", uptime))
    dp.add_handler(CommandHandler("unsinn", unsinn))

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
