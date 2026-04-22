#!/usr/bin/env node
/**
 * discord-slash-handler.js — Handle Discord slash command interactions.
 *
 * Runs as a persistent process alongside the cron runner.
 * Listens for interactionCreate events via discord.js gateway.
 *
 * Usage:
 *   node scripts/discord-slash-handler.js
 *
 * Environment:
 *   DISCORD_BOT_TOKEN, DISCORD_APP_ID, WORKSPACE_DIR
 */

'use strict';

const { Client, GatewayIntentBits } = require('discord.js');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const WORKSPACE = process.env.WORKSPACE_DIR || '/workspace';
const MODEL_STATE_FILE = path.join(WORKSPACE, 'data', 'current-model.json');
const JOBS_FILE = path.join(WORKSPACE, 'crons', 'jobs.json');

const MODEL_ALIASES = {
  opus: 'claude-opus-4-6',
  sonnet: 'claude-sonnet-4-6',
  haiku: 'claude-haiku-4-5',
};

function readCurrentModel() {
  try {
    return JSON.parse(fs.readFileSync(MODEL_STATE_FILE, 'utf8')).model || 'sonnet';
  } catch {
    return 'sonnet';
  }
}

function setModel(alias) {
  const model = alias in MODEL_ALIASES ? alias : 'sonnet';
  fs.writeFileSync(MODEL_STATE_FILE, JSON.stringify({ model, updatedAt: new Date().toISOString() }));
  return model;
}

function runClaude(prompt, model = 'sonnet') {
  return new Promise((resolve, reject) => {
    const fullModel = MODEL_ALIASES[model] || MODEL_ALIASES.sonnet;
    let output = '';
    const proc = spawn('claude', [
      '--dangerously-skip-permissions',
      '--model', fullModel,
      '-p', prompt,
    ], { env: process.env });

    proc.stdout.on('data', d => output += d);
    proc.stderr.on('data', d => console.error('[claude stderr]', d.toString()));

    const timer = setTimeout(() => { proc.kill(); resolve(output || '(timed out)'); }, 60000);

    proc.on('close', () => {
      clearTimeout(timer);
      resolve(output.trim() || '(no output)');
    });
    proc.on('error', reject);
  });
}

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

client.on('interactionCreate', async (interaction) => {
  if (!interaction.isChatInputCommand()) return;

  const { commandName } = interaction;
  await interaction.deferReply();

  try {
    if (commandName === 'status') {
      const result = await runClaude(
        'Run a quick system status check: check Docker containers if accessible, ' +
        'report memory usage, and list any recent errors from memory/errors.md if it exists. ' +
        'Keep the response under 300 words.'
      );
      await interaction.editReply(result.slice(0, 1900));

    } else if (commandName === 'model') {
      const name = interaction.options.getString('name');
      if (!name) {
        const current = readCurrentModel();
        await interaction.editReply(`Current model: **${current}** (${MODEL_ALIASES[current] || current})`);
      } else if (!(name in MODEL_ALIASES)) {
        await interaction.editReply(`Unknown model. Available: ${Object.keys(MODEL_ALIASES).join(', ')}`);
      } else {
        setModel(name);
        await interaction.editReply(`Model set to **${name}**. Session will use it on next restart.`);
      }

    } else if (commandName === 'herc') {
      const message = interaction.options.getString('message');
      const result = await runClaude(message, readCurrentModel());
      await interaction.editReply(result.slice(0, 1900));

    } else if (commandName === 'cron') {
      const sub = interaction.options.getSubcommand();

      if (sub === 'list') {
        let jobs = [];
        try { jobs = JSON.parse(fs.readFileSync(JOBS_FILE, 'utf8')).jobs || []; } catch {}
        const enabled = jobs.filter(j => j.enabled);
        if (!enabled.length) {
          await interaction.editReply('No enabled cron jobs.');
        } else {
          const lines = enabled.map(j => `• **${j.id}** — ${j.name} \`${j.schedule}\``);
          await interaction.editReply(lines.join('\n').slice(0, 1900));
        }

      } else if (sub === 'run') {
        const id = interaction.options.getString('id');
        let jobs = [];
        try { jobs = JSON.parse(fs.readFileSync(JOBS_FILE, 'utf8')).jobs || []; } catch {}
        const job = jobs.find(j => j.id === id);
        if (!job) {
          await interaction.editReply(`Job not found: ${id}`);
        } else {
          await interaction.editReply(`Running **${job.name}**...`);
          runClaude(job.message, job.model || 'sonnet').then(result => {
            interaction.followUp(result.slice(0, 1900)).catch(() => {});
          });
        }
      }
    }
  } catch (err) {
    console.error('[slash]', err);
    await interaction.editReply(`Error: ${err.message}`).catch(() => {});
  }
});

client.once('ready', () => {
  console.log(`[slash] Logged in as ${client.user.tag}`);
});

client.login(process.env.DISCORD_BOT_TOKEN).catch(err => {
  console.error('[slash] Failed to login:', err.message);
  process.exit(1);
});
