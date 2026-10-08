// Silent stand-in for the app's sound player. The engine calls Sound.play when
// Klay reacts (slap, greet, annoyed); the render bench has no audio, so this
// does nothing. The 29 WAVs live in NotchBuddy/Resources/sounds/.

export const Sound = {
  play(_name: string): void {},
};
