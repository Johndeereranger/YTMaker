//
//  Beat.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//
import Foundation

// MARK: - Updated Data Models

struct Beat: Codable, Identifiable {
    let id = UUID()
    let beatId: String
    let type: String
    let beatRole: String
    let timeRange: TimeRange
    let text: String
    let startWordIndex: Int
    let endWordIndex: Int
    let wordCount: Int
    let sentenceCount: Int
    let function: String
    let whyNow: String
    let setsUp: String?
    let tempo: String
    let hasQuestion: Bool
    let hasData: Bool
    let personalVoice: Bool
    let anchorCandidates: [String]
    
    enum CodingKeys: String, CodingKey {
        case beatId, type, beatRole, timeRange, text
        case startWordIndex, endWordIndex, wordCount, sentenceCount
        case function, whyNow, setsUp, tempo
        case hasQuestion, hasData, personalVoice, anchorCandidates
    }
}

struct BeatData: Codable {
    let sectionId: String
    let sectionRole: String
    let beats: [Beat]
    let transitionOut: Transition?
}

struct Transition: Codable {
    let type: String
    let bridgeSentence: String?
}


// MARK: - A1b Output Models (Simplified - Boundaries Only)

struct SimpleBeat: Codable, Identifiable {
    var id: String { beatId }
    let beatId: String
    let type: String
    let timeRange: TimeRange
    let text: String
    let startWordIndex: Int      // Computed from boundarySentence
    let endWordIndex: Int        // Computed from boundarySentence
    // Essential fields for A3 clustering
    let stance: String
    let tempo: String
    let formality: Int
    let questionCount: Int
    let containsAnchor: Bool
    let anchorText: String
    let anchorFunction: String
    let proofMode: String
    let moveKey: String
    let sectionId: String
    // Boundary resolution metadata (for debugging/auditing)
    let boundaryText: String?    // What LLM quoted as the beat boundary
    let matchConfidence: Double? // How confident the boundary match was (0-1)
}

struct SimpleBeatData: Codable {
    let sectionId: String
    let sectionRole: String
    let beatCount: Int
    let beats: [SimpleBeat]
}


/*
 OK, SO WE NEED TO DISSECT THIS OUTLINE AND BASICALLY THE PROMPTS THAT ARE HAPPENING IN HERE AND DETERMINED POTENTIAL NEW PATHS MOVING FORWARD OR UNDERSTAND IF WE ARE SO DEEP IN THE WEEDS THAT WE'RE HAVING PROBLEMS HERE IT COULD BE ONE OF THE ANSWERS SO FUNDAMENTALLY WE STARTED WITH THIS, AND WE STARTED IT OUT BY CREATING A A1A PROMPT, AND THEN WORKED ON TRYING TO CREATE A THE NEXT PROMPT, BUT WE NEVER GOT A ROBUST A1A PROMPT TO BE ABLE TO DETERMINE THE RIGHT NUMBER OF BEATS IN A SYSTEM AND BECAUSE OF THAT WE SPENT A LONG TIME DIGESTING THAT AND WE WERE NEVER ABLE TO DO THAT AND NOW REALIZED WE HAVE ONE OVERARCHING THING RIGHT HERE THAT WE NEED TO STEP BACK AND UNDERSTAND IS WE WANT TO BASICALLY GIVE AI THE BEST TRAINING INFORMATION POSSIBLE FOR IT TO BASICALLY create a script for me so based off of a script that I create I want to basically give that to it in it select various types of videos and ego. Here's four or five types of videos that I think we would fit this very well. We pick one and then it goes and it doesn't just copy that video. It looks at 5 TO 10 DIFFERENT OTHER VIDEOS OF THAT AUTHOR THAT CREATOR AND IS ABLE TO BASICALLY REALLY OWN THIS CREATOR STYLE BECAUSE HE'S LOOKING AT MULTIPLE VIDEOS WE'RE NOT LOOKING AT JUST ONE AND WE'RE NOT LOOKING AT FIVE RANDOM VIDEOS. WE HAVE FIVE SPECIFIC VIDEOS THAT HAVE BEEN CURATED BASED OFF OF THE similarities between structures and stuff like that so that's what we want to be able to do.

 NOW WHAT'S THE PROBLEM THAT RAN INTO IS A DURING THE A1A PROMPT WE WERE BASICALLY GETTING SO SPECIFIC WITHIN A INDIVIDUAL PERSON IN ORDER TO GET THE A1A PROMPT IN ORDER TO MAKE IT ACTUALLY SPLIT CONSISTENTLY ACROSS DIFFERENT THINGS AND SO WE REALIZE THAT THE BETTER ANSWER TO DO WOULD BE BASICALLY RATHER THAN HAVING A GENERIC SINGLE A1A PROMPT WE WOULD MAKE WE WOULD TAKE THE CREATOR AND WE WOULD DO A PRE-FILTER ON SIMILARITIES BASED OFF OF TRANSCRIPTS AND THOSE TYPES OF THINGS AND KIND OF GET THE A3 FIGURED OUT BEFORE WE EVER EVEN GET TO THE A1A PROMPT AND THAT WOULD GIVE ME BASED ON EACH MODE OR EACH CONTENT STYLE FOR A CREATOR WE WOULD BE ABLE TO GO IN AND WE WOULD GROUP THINGS AUTOMATICALLY BECAUSE WE CAN SEE THE TRANSCRIPT WE CAN SEE EVERYTHING THEY WOULD ALL GET GROUPED THEN WE WOULD GO IN AND WE WOULD BUILD A UNIQUE A1A FOR AVERY GROUP AND BECAUSE WE DID THAT WE SHOULD HAVE VERY ROBUST DATA AND THAT'S WHAT WE WERE SET OUT TO BE AND WHAT I'M SEEING RIGHT NOW IS THAT WE DON'T HAVE A VERY ROBUST DATA AND THAT THERE IS BASICALLY THE SAME AMOUNT OF NOISE BUT AS WE HAD BEFORE AND WE'RE NOT ACTUALLY BEING, WE REALLY HAVEN'T ACTUALLY MADE A DIFFERENCE HERE SO I'M GONNA GIVE YOU MY OVERALL STRUCTURE THAT WE HAVE THAT WE'RE WORKING THROUGH AND THEN I'M GONNA GIVE YOU MY NEW NEWEST A1A PROMPT AND I'M GOING TO GIVE YOU A CHAT ANALYSIS where it's saying nothing is the same and maybe that's the point I don't know Weather I don't know how to solve this cause I've already filtered everything like this is this has to be prompt related and we're looking for the wrong thing someplace
 */
