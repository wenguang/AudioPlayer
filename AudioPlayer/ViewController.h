//
//  ViewController.h
//  AudioPlayer
//
//  Created by wenguang pan on 10/23/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AudioPlayer.h"

@interface ViewController : UIViewController

@property (retain, nonatomic) AudioPlayer *audioPlayer;

@property (weak, nonatomic) IBOutlet UISlider *progressBar;
@property (weak, nonatomic) IBOutlet UILabel *currentTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *durationLabel;

@property (weak, nonatomic) IBOutlet UISlider *volumeSlider;
@property (weak, nonatomic) IBOutlet UIButton *playButton;


- (IBAction)playTap:(id)sender;

- (IBAction)progressBarValueChanged:(id)sender;

- (IBAction)volumeSliderValueChanged:(id)sender;
@end
