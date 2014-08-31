//
//  ViewController.m
//  AudioPlayer
//
//  Created by wenguang pan on 10/23/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"

@interface ViewController ()

@end

@implementation ViewController

@synthesize audioPlayer;
@synthesize progressBar;
@synthesize currentTimeLabel;
@synthesize durationLabel;
@synthesize volumeSlider;
@synthesize playButton;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    //
    // testing
    //
     [self setAudioPlayer:[[AudioPlayer alloc] initWithURL:[NSURL URLWithString:@"http://zhangmenshiting.baidu.com/data2/music/8473663/2164227183600128.mp3?xcode=d762c64b7e35bc3cce3f617227bd56970d378418f80bcfb9&song_id=2164227"]]];
    
    //http://zhangmenshiting.baidu.com/data2/music/8473663/2164227183600128.mp3?xcode=d762c64b7e35bc3cce3f617227bd56970d378418f80bcfb9&song_id=2164227
}

- (void)viewDidUnload
{
    [self setAudioPlayer:nil];
    
    [self setProgressBar:nil];
    [self setCurrentTimeLabel:nil];
    [self setDurationLabel:nil];
    [self setVolumeSlider:nil];
    [self setPlayButton:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (IBAction)playTap:(id)sender 
{
    //
    // testing
    //
    [audioPlayer start];
}

- (IBAction)progressBarValueChanged:(id)sender {
}

- (IBAction)volumeSliderValueChanged:(id)sender {
}
@end
