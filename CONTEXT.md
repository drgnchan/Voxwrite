# Voice Writing

This context describes a system-wide assistant that turns speech into usable text in the application where the user is currently working.

## Language

**Voice Session**:
One continuous interaction from choosing a voice mode through inserting or presenting its result.
_Avoid_: Recording job, transcription task

**Voice Mode**:
The intent applied to a Voice Session: Dictation, Translation, or Ask.
_Avoid_: Feature, command type

**Dictation**:
A Voice Mode that turns spoken thoughts into cleaned, structured text in the speaker's language.
_Avoid_: Raw transcription, speech-to-text

**Translation**:
A Voice Mode that turns speech into polished text in one chosen Translation Target.
_Avoid_: Translate command

**Translation Target**:
The persisted output language used only by Translation; Dictation preserves the source language.
_Avoid_: Default output locale

**Ask**:
A Voice Mode that uses speech as an instruction or question, optionally grounded in selected text.
_Avoid_: Chat, assistant mode

**Text Target**:
The focused editable surface in another application where a Voice Session result should be inserted.
_Avoid_: Text box, destination app

**Personal Dictionary**:
The user's collection of names and terms that should be recognized and spelled consistently.
_Avoid_: Vocabulary list, glossary

**Writing Profile**:
The user's learned preferences for tone, structure, formatting, and recurring corrections.
_Avoid_: AI personality, style model

**History Entry**:
A local, text-only record of a completed Voice Session containing its mode, ASR transcript, final output, and completion time. Raw audio is excluded.
_Avoid_: Log, transcript record

**Voice Activity Policy**:
The thresholds and duration rules that confirm speech, reject accidental triggers, stop after trailing silence, and cap recording length.
_Avoid_: Silence timer, auto-stop hack

**Cloud Provider**:
An external service that performs speech recognition, writing transformation, or both.
_Avoid_: AI backend, model vendor
