/* 
   NSSpellChecker.m

   Description...

   Copyright (C) 1996, 2000 Free Software Foundation, Inc.

   Author:  Gregory John Casamento <greg_casamento@yahoo.com>
   Date: 2000

   Author:  Scott Christley <scottc@net-community.com>
   Date: 1996
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/ 

#include <gnustep/gui/config.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSProxy.h>
#include <Foundation/NSBundle.h>
#include <Foundation/NSUtilities.h>
#include <Foundation/NSValue.h>
#include <AppKit/NSNibLoading.h>
#include <AppKit/NSSpellChecker.h>
#include <AppKit/NSSpellServer.h>
#include <AppKit/NSTextField.h>
#include <AppKit/NSPopUpButton.h>
#include <AppKit/IMLoading.h>
#include <AppKit/GSServicesManager.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSMatrix.h>
#include <AppKit/NSBrowser.h>
#include <AppKit/NSBrowserCell.h>
#include <AppKit/NSScrollView.h>

// prototype for function to create name for server
NSString *GSSpellServerName(NSString *checkerDictionary,
			     NSString *language);

// These are methods which we only want the NSSpellChecker to call.
// The protocol is defined here so that the outside world does not
// have access to these internal methods.
@protocol NSSpellServerPrivateProtocol
- (NSRange)_findMisspelledWordInString: (NSString *)stringToCheck
			      language: (NSString *)language
		   learnedDictionaries: (NSArray *)dictionaries
			     wordCount: (int *)wordCount
			     countOnly: (BOOL)countOnly;
-(BOOL)_learnWord: (NSString *)word
     inDictionary: (NSString *)language;
-(BOOL)_forgetWord: (NSString *)word
      inDictionary: (NSString *)language;
- (NSArray *)_suggestGuessesForWord: (NSString *)word
			 inLanguage: (NSString *)language;
@end

// Methods needed to get the GSServicesManager
@interface NSApplication(NSSpellCheckerMethods)
- (GSServicesManager *)_listener;
@end

@implementation NSApplication(NSSpellCheckerMethods)
- (GSServicesManager *)_listener
{
  return _listener;
}
@end

// Methods in the GSServicesManager to launch the spell server.
@interface GSServicesManager(NSSpellCheckerMethods)
- (id)_launchSpellCheckerForLanguage: (NSString *)language;
- (NSArray *)_languagesForPopUpButton;
@end

@implementation GSServicesManager(NSSpellCheckerMethods)
- (id)_launchSpellCheckerForLanguage: (NSString *)language
{
  id proxy = nil;
  NSDictionary *spellCheckers = [allServices objectForKey: @"BySpell"];
  NSDictionary *checkerDictionary = [spellCheckers objectForKey: language];
  NSString *spellServicePath = [checkerDictionary objectForKey: @"ServicePath"];
  NSString *vendor = [checkerDictionary objectForKey: @"NSSpellChecker"];
  NSDate *finishBy;

  NSString *port = GSSpellServerName(vendor, language);
  double seconds = 30.0;

  NSLog(@"Spell Checker Dictionary: %@", spellCheckers);
  NSLog(@"Language: %@", language);
  NSLog(@"Service to start: %@", spellServicePath);
  NSLog(@"Port: %@",port);

  finishBy = [NSDate dateWithTimeIntervalSinceNow: seconds];
  proxy = GSContactApplication(spellServicePath, port, finishBy);
  if (proxy == nil)
    {
      NSRunAlertPanel(nil,
	[NSString stringWithFormat:
	    @"Failed to contact spell checker for language '%@'", language],
	@"Continue", nil, nil);
    }
  else
    {
      NSLog(@"Set proxy");
      [(NSDistantObject *)proxy 
			  setProtocolForProxy: @protocol(NSSpellServerPrivateProtocol)];
    }
			  
  return proxy;
}

- (NSArray *)_languagesForPopUpButton
{
  NSDictionary *spellCheckers = [allServices objectForKey: @"BySpell"];
  NSArray *allKeys = [spellCheckers allKeys];

  return allKeys;
}
@end

// Shared spell checker instance....
static NSSpellChecker *__sharedSpellChecker = nil;
static int __documentTag = 0;

// Implementation of spell checker class
@implementation NSSpellChecker
//
// Class methods
//
+ (void)initialize
{
  if (self == [NSSpellChecker class])
    {
      // Initial version
      [self setVersion:1];
    }
}

//
// Making a Checker available 
//
+ (NSSpellChecker *)sharedSpellChecker
{
  // Create the shared instance.
  if(__sharedSpellChecker == nil)
    {
      __sharedSpellChecker = [[NSSpellChecker alloc] init];
    }
  return __sharedSpellChecker;
}

+ (BOOL)sharedSpellCheckerExists
{
  // If the spell checker has been created, the 
  // variable will not be nil.
  return (__sharedSpellChecker != nil);
}

//
// Managing the Spelling Process 
//
+ (int)uniqueSpellDocumentTag
{
  NSLog(@"returning unique spell document tag");
  return ++__documentTag;
}

//
// Internal methods for use by the spellChecker GUI
//
- (void)_populateDictionaryPulldown: (NSArray *)dictionaries;
{
  [_dictionaryPulldown removeAllItems];
  [_dictionaryPulldown addItemsWithTitles: dictionaries];
  [_dictionaryPulldown selectItemWithTitle: _language];
}

- (void)_populateAccessoryView: (NSArray *)words
{
  NSLog(@"Populate accessory view.......... %@", words);
}

- (void)_handleServerDeath: (NSNotification *)notification
{
  NSLog(@"Spell server died");
  RELEASE(_serverProxy);
  _serverProxy = nil;
}

// Support function to start the spell server
- (id)_startServerForLanguage: (NSString *)language
{
  id proxy = nil;
  // Start the service for this language  
  proxy = [[NSApp _listener] _launchSpellCheckerForLanguage: language];
  
  if(proxy == nil)
    {
      NSLog(@"Failed to get the spellserver");
      return nil;
    }
  
  // Retain the proxy, if we got the connection.
  // Also make sure that we handle the death of the server
  // correctly.
  [[NSNotificationCenter defaultCenter]
    addObserver: self
    selector: @selector(_handleServerDeath:)
    name: NSConnectionDidDieNotification
    object: [(NSDistantObject *)proxy connectionForProxy]];

  return proxy;
}

- (id)_serverProxy
{
  if(_serverProxy == nil)
    {
      id proxy = [self _startServerForLanguage: _language];
      if(proxy != nil)
	{
	  _serverProxy = proxy;
	  RETAIN(_serverProxy);
	}
    }
  return _serverProxy;
}

//
// Instance methods
//
- init
{
  NSArray *userLanguages = [NSUserDefaults userLanguages];  

  // Set the language to the default for the user.
  [super init];
  _language = [userLanguages objectAtIndex: 0];
  _wrapFlag = NO;
  _position = 0;
  _spellPanel = nil;
  _serverProxy = nil;
  _currentTag = 0;
  _ignoredWords = [NSMutableDictionary dictionary];
  
  // Start the server and retain the reference to the
  // proxy.
  [self _serverProxy];
  RETAIN(_ignoredWords);

  // Load the gmodel file
  if(![GMModel loadIMFile: @"SpellPanel"
	       owner: self])
    {
      NSLog(@"NIB file load failed for SpellPanel");
      return nil;
    }


  return self;
}

- (void)dealloc
{
  RELEASE(_ignoredWords);
  RELEASE(_serverProxy);
}

//
// Managing the Spelling Panel 
//
- (NSView *)accessoryView
{
  return _accessoryView;
}

- (void)setAccessoryView:(NSView *)aView
{
  _accessoryView = aView;
}

- (NSPanel *)spellingPanel
{
  return _spellPanel;
}


//
// Checking Spelling 
//
- (int)countWordsInString:(NSString *)aString
		 language:(NSString *)language
{
  int count = 0;
  NSRange r = NSMakeRange(0,0);
  r = [[self _serverProxy] _findMisspelledWordInString: aString
			   language: _language
			   learnedDictionaries: nil
			   wordCount: &count
			   countOnly: YES];
  
  return count;
}

- (NSRange)checkSpellingOfString:(NSString *)stringToCheck
		      startingAt:(int)startingOffset
{
  int wordCount = 0;
  NSRange r = NSMakeRange(0,0);
  
  r = [self checkSpellingOfString: stringToCheck
	    startingAt: startingOffset
	    language: _language
	    wrap: NO
	    inSpellDocumentWithTag: 0
	    wordCount: &wordCount];

  return r;
}

- (NSRange)checkSpellingOfString:(NSString *)stringToCheck
		      startingAt:(int)startingOffset
                        language:(NSString *)language
		            wrap:(BOOL)wrapFlag
          inSpellDocumentWithTag:(int)tag
		       wordCount:(int *)wordCount
{
  NSRange r = NSMakeRange(0,0);
  NSString *misspelledWord = nil;
  NSArray *dictForTag = [self ignoredWordsInSpellDocumentWithTag: tag],
    *suggestedWords = nil;
  
  _currentTag = tag;
  // We have no string to work with
  if(stringToCheck == nil)
    {
      return NSMakeRange(0,0);
    }
  else
    // The string is zero length
    if([stringToCheck length] == 0)
      {
	return NSMakeRange(0,0);
      }

  // Do this in an exception handling block in ensure that a failure of the
  // spellserver does not bring down the application.
  NS_DURING
    {
      // Get the substring and check it.
      NSString *substringToCheck = [stringToCheck substringFromIndex: startingOffset];
      r = [[self _serverProxy] _findMisspelledWordInString: substringToCheck
			       language: _language
			       learnedDictionaries: dictForTag
			       wordCount: wordCount
			       countOnly: NO];
      
      if(r.length != 0)
	{
	  // Adjust results relative to the original string
	  r.location += startingOffset;
	}
      else
	{
	  if(wrapFlag)
	    {
	      // Check the second half of the string
	      NSString *firstHalfOfString = [stringToCheck 
					      substringToIndex: startingOffset];
	      r = [[self _serverProxy] _findMisspelledWordInString: firstHalfOfString
				       language: _language
				       learnedDictionaries: dictForTag
				       wordCount: wordCount
				       countOnly: NO];
	    }
	}

      misspelledWord = [stringToCheck substringFromRange: r];
      suggestedWords = [[self _serverProxy] _suggestGuessesForWord: misspelledWord
					    inLanguage: _language];
    }
  NS_HANDLER
    {
      NSLog(@"%@",[localException reason]);
    }
  NS_ENDHANDLER
    
  [self updateSpellingPanelWithMisspelledWord: misspelledWord];
  [self _populateAccessoryView: suggestedWords];

  return r;
}

//
// Setting the Language 
//
- (NSString *)language
{
  return _language;
}

- (BOOL)setLanguage:(NSString *)aLanguage
{
  int index = 0;
  BOOL result = NO;

  index = [_dictionaryPulldown indexOfItemWithTitle: aLanguage];
  if(index != -1)
    {
      [_dictionaryPulldown selectItemAtIndex: index];
      result = YES;
    }

  return result;
}

//
// Managing the Spelling Process 
//

// Remove the ignored word list for this 
// document from the dictionary
- (void)closeSpellDocumentWithTag:(int)tag
{
  NSNumber *key = [NSNumber numberWithInt: tag];
  [_ignoredWords removeObjectForKey: key];
}

// Add a word to the ignored list.
- (void)    ignoreWord:(NSString *)wordToIgnore 
inSpellDocumentWithTag:(int)tag
{
  NSNumber *key = [NSNumber numberWithInt: tag];
  NSMutableSet *words = [_ignoredWords objectForKey: key];

  NSLog(@"Ignore: %@",wordToIgnore);
  if(![wordToIgnore isEqualToString: @""])
    {
      // If there is a dictionary add to it, if not create one.
      if(words == nil)
	{
	  words = [NSMutableSet setWithObject: wordToIgnore];
	  [_ignoredWords setObject: words forKey: key];
	}
      else
	{
	  [words addObject: wordToIgnore];
	}
    }
  NSLog(@"Words to ignore %@ for doc# %d", words, tag); 

}

// get the list of ignored words.
- (NSArray *)ignoredWordsInSpellDocumentWithTag:(int)tag
{
  NSNumber *key = [NSNumber numberWithInt: tag];
  NSSet *words = [_ignoredWords objectForKey: key];
  return [words allObjects];
}

// set the list of ignored words for a given document
- (void)setIgnoredWords:(NSArray *)someWords
 inSpellDocumentWithTag:(int)tag
{
  NSNumber *key = [NSNumber numberWithInt: tag];
  NSSet *words = [NSSet setWithArray: someWords];
  [_ignoredWords setObject: words forKey: key];
}

- (void)setWordFieldStringValue:(NSString *)aString
{
  [_wordField setStringValue: aString];
}

- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word
{
  [self setWordFieldStringValue: word];
}

- _learn: (id)sender
{
  NSString *word = [_wordField stringValue];
  BOOL result = NO;

  // Call server and record the learned word.
  NS_DURING
    {
      result = [[self _serverProxy] _learnWord: word
				    inDictionary: _language];
    }
  NS_HANDLER
    {
      NSLog(@"%@",[localException reason]);
    }
  NS_ENDHANDLER

  return self;
}

- _forget: (id)sender
{
  NSString *word = [_wordField stringValue];
  BOOL result = NO;

  // Call the server and remove the word from the learned
  // list.
  NS_DURING
    {
      result = [[self _serverProxy] _forgetWord: word
				    inDictionary: _language];
    }
  NS_HANDLER
    {
      NSLog(@"%@",[localException reason]);
    }
  NS_ENDHANDLER

  return self;
}

- _ignore: (id)sender
{
  BOOL processed = NO;
  id responder = [[[[NSApplication sharedApplication] mainWindow] contentView] documentView];

  processed = [responder tryToPerform: @selector(ignoreSpelling:)
			 with: _wordField];
  if(!processed)
    {
      NSLog(@"_ignore: No responder found");
    }

  return self;
}

- _guess: (id)sender
{
  NSString *word = [_wordField stringValue];
  NSArray *guesses = nil;

  NS_DURING
    {
      guesses = [[self _serverProxy] _suggestGuessesForWord: word
				     inLanguage: _language];
      if(guesses == nil)
	{
	  NSLog(@"Nil array returned from server");
	}
      else
	{
	  // Fill in the view...
	  [self _populateAccessoryView: guesses];
	}
    }
  NS_HANDLER
    {
      NSLog(@"%@",[localException reason]);
      guesses = nil;
    }
  NS_ENDHANDLER

  return self;
}

- _findNext: (id)sender
{
  BOOL processed = NO;
  id responder = [[[[NSApplication sharedApplication] mainWindow] contentView] documentView];

  processed = [responder tryToPerform: @selector(checkSpelling:)
			 with: _spellPanel];
  if(!processed)
    {
      NSLog(@"Call to checkSpelling failed.  No responder found");
    }

  return self;
}

- _correct: (id)sender
{
  BOOL processed = NO;
  id responder = [[[[NSApplication sharedApplication] mainWindow] contentView] documentView];

  processed = [responder tryToPerform: @selector(changeSpelling:)
			 with: _wordField];
  if(!processed)
    {
      NSLog(@"Call to changeSpelling failed.  No responder found");
    }

  return self;
}

- _switchDictionary: (id)sender
{
  id proxy = nil;
  NSString *language = nil;

  // Start the service for this language  
  language = [_dictionaryPulldown stringValue];
  if(![language isEqualToString: _language])
    {
      NSLog(@"Language = %@",language);
      proxy = [self _startServerForLanguage: language];
      if(proxy != nil)
	{
	  ASSIGN(_language, language);
	  RELEASE(_serverProxy);
	  _serverProxy = proxy;
	  RETAIN(_serverProxy);
	}
      else
	{
	  // Reset the pulldown to the proper language.
	  [_dictionaryPulldown selectItemWithTitle: _language];
	}
    }

  return self;
}

-(void) awakeFromNib
{
  [self _populateDictionaryPulldown: 
	  [[NSApp _listener] _languagesForPopUpButton]];
  [_accessoryView setDelegate: self];
}
@end

@implementation NSSpellChecker(NSBrowserDelegate)
- (BOOL) browser: (NSBrowser*)sender 
       selectRow: (int)row
	inColumn: (int)column
{
  return YES;
}

- (void)    browser: (NSBrowser *)sender 
createRowsForColumn: (int)column
	   inMatrix: (NSMatrix *)matrix
{
  NSLog(@"Create rows");
}

- (NSString*) browser: (NSBrowser*)sender  
	titleOfColumn: (int)column
{
  return @"Guess";
}

- (void) browser: (NSBrowser *)sender 
 willDisplayCell: (id)cell 
	   atRow: (int)row 
	  column: (int)column
{
  NSLog(@"reached 1....");
}

/*
- (BOOL) browser: (NSBrowser *)sender 
   isColumnValid: (int)column
{
  NSLog(@"reached 3....");
  return NO;
}
*/
@end
