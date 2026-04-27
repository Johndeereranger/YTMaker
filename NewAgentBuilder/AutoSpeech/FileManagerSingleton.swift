//
//  FileManagerSingleton.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//


import Foundation
import UIKit
import AVFoundation

class FileManagerSingleton {
    static let instance = FileManagerSingleton()
    
    private let audioDirectory = "AudioFiles"
    private let imageDirectory = "ImageFiles"
    
    private init() {}
    
    func storeAudioAsWAV(beat: SoundBeat, audioData: Data){
       
        let audioFilename = "\(beat.id)-audio.wav"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioFileURL = documentsDirectory.appendingPathComponent(audioFilename)
        do {
            try audioData.write(to: audioFileURL, options: .atomic)
            print(#function, audioFileURL)
          //  MovieDataManager.instance.verseGotSpeech(bcv: BCV(book: book, chapter: chapter, verse: prompt))
        } catch {
            print(#function, "failed", self)
        }
    }
    
    func getAudioWAVFileURL(beat: SoundBeat) -> URL? {
        let audioFilename = "\(beat.id)-audio.wav"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioFileURL = documentsDirectory.appendingPathComponent(audioFilename)
        if FileManager.default.fileExists(atPath: audioFileURL.path) {
            return audioFileURL
        } else {
            return nil
        }
    }
    
    func audioFileExists(for beat: SoundBeat) -> Bool {
        let filename = "\(beat.id)-audio.wav"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
