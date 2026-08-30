/**
 * First run: a name, a thing to work on, and something to grow.
 *
 * Three questions, because the fewest that produce a usable garden is three.
 * Anything more is a form standing between someone and the thing they came to
 * do, and every answer here is changeable afterwards.
 *
 * Starter projects are seeded the way the desktop seeds them - ordinary
 * categories, deletable and renamable, not special-cased anywhere - so a new
 * player can start a session immediately instead of being made to invent a
 * taxonomy first.
 */

import { useMemo, useState } from "react";

import { PlantView } from "../components/PlantView.js";
import { ALL_SPECIES } from "../../content/content.js";
import type { PlantSpecies } from "../../domain/species.js";
import { RARITY_NAMES, getDisplayFocusMinutes } from "../../domain/species.js";
import { formatDuration } from "../../domain/time-util.js";
import { useTheme } from "../usePlatform.js";

/**
 * The species offered on day one: available from the start, not hidden, and
 * cheap enough that the first one matures inside a week of ordinary use.
 */
const STARTER_LIMIT = 6;

export interface OnboardingResult {
  displayName: string;
  projectName: string;
  speciesId: string;
}

interface Props {
  onComplete: (result: OnboardingResult) => void;
}

const SUGGESTED_PROJECTS = ["Studying", "Work", "Reading", "Programming", "Personal"];

export function OnboardingScreen({ onComplete }: Props) {
  const { foliageAmbient } = useTheme();
  const [step, setStep] = useState(0);
  const [displayName, setDisplayName] = useState("");
  const [projectName, setProjectName] = useState("");
  const [speciesId, setSpeciesId] = useState("");

  const starters = useMemo<PlantSpecies[]>(
    () => ALL_SPECIES
      .filter((s) => !s.hiddenUntilDiscovered && s.unlockRequirement === null && s.morphology !== null)
      .slice(0, STARTER_LIMIT),
    [],
  );

  const canContinue = step === 0
    ? displayName.trim() !== ""
    : step === 1
      ? projectName.trim() !== ""
      : speciesId !== "";

  const finish = (): void => {
    onComplete({
      displayName: displayName.trim(),
      projectName: projectName.trim(),
      speciesId,
    });
  };

  return (
    <div className="onboarding">
      <ol className="onboarding__steps" aria-label="Setup progress">
        {["You", "Your work", "Your first plant"].map((label, index) => (
          <li key={label} aria-current={index === step ? "step" : undefined}>
            <span className="onboarding__dot" />
            {label}
          </li>
        ))}
      </ol>

      {step === 0 && (
        <section className="onboarding__panel">
          <h1>What should the garden call you?</h1>
          <p>Only ever shown to you. You can change it later.</p>
          <input
            className="field-input"
            type="text"
            value={displayName}
            maxLength={40}
            autoFocus
            placeholder="Your name"
            aria-label="Your name"
            onChange={(e) => setDisplayName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && canContinue) setStep(1);
            }}
          />
        </section>
      )}

      {step === 1 && (
        <section className="onboarding__panel">
          <h1>What are you working on?</h1>
          <p>
            Sessions get filed under this, so your statistics can tell revision
            apart from everything else. Add as many as you like later.
          </p>
          <input
            className="field-input"
            type="text"
            value={projectName}
            maxLength={60}
            autoFocus
            placeholder="Piano practice"
            aria-label="What you are working on"
            onChange={(e) => setProjectName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && canContinue) setStep(2);
            }}
          />
          <div className="chips">
            {SUGGESTED_PROJECTS.map((name) => (
              <button
                key={name}
                type="button"
                className="chip"
                onClick={() => setProjectName(name)}
              >
                {name}
              </button>
            ))}
          </div>
        </section>
      )}

      {step === 2 && (
        <section className="onboarding__panel">
          <h1>Pick something to grow</h1>
          <p>
            It grows from the time you actually spend focusing, and nothing else.
            There is no way to water it, hurry it, or lose it.
          </p>
          <div className="starter-grid">
            {starters.map((species) => {
              const minutes = getDisplayFocusMinutes(species);
              return (
                <button
                  key={species.id}
                  type="button"
                  className="starter"
                  aria-pressed={species.id === speciesId}
                  onClick={() => setSpeciesId(species.id)}
                >
                  <PlantView
                    morphology={species.morphology!}
                    pot={null}
                    growth={1}
                    width={104}
                    height={132}
                    seed={species.id}
                    lod={0.5}
                    foliageAmbient={foliageAmbient}
                  />
                  <span className="starter__name">{species.displayName}</span>
                  <span className="binomial">{species.scientificName}</span>
                  <span className="starter__cost">
                    {minutes > 0 ? formatDuration(minutes) : RARITY_NAMES[species.rarity]}
                  </span>
                </button>
              );
            })}
          </div>
        </section>
      )}

      <div className="onboarding__actions">
        {step > 0 && (
          <button className="btn btn--quiet" type="button" onClick={() => setStep(step - 1)}>
            Back
          </button>
        )}
        <button
          className="btn"
          type="button"
          disabled={!canContinue}
          onClick={() => (step === 2 ? finish() : setStep(step + 1))}
        >
          {step === 2 ? "Plant it" : "Continue"}
        </button>
      </div>
    </div>
  );
}
