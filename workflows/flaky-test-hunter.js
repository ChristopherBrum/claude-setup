export const meta = {
  name: 'flaky-test-hunter',
  description: 'Run suspect specs repeatedly in parallel and classify each as flaky, failing, or stable',
  phases: [
    { title: 'Hunt', detail: 'run each spec N times and classify' },
    { title: 'Summarize', detail: 'aggregate flaky vs failing vs stable' },
  ],
}

// Accepts either { specs: [...], runs: N } or a bare array of spec paths.
const specs = Array.isArray(args) ? args : (Array.isArray(args?.specs) ? args.specs : [])
const runs = (args && typeof args === 'object' && args.runs) ? args.runs : 5

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['spec', 'passes', 'failures', 'classification', 'notes'],
  properties: {
    spec: { type: 'string' },
    passes: { type: 'integer' },
    failures: { type: 'integer' },
    classification: { type: 'string', enum: ['stable', 'flaky', 'failing'] },
    notes: { type: 'string', description: 'For flaky/failing: the failing example(s) and error summary.' },
  },
}

let out = { flaky: [], failing: [], stable: [], all: [] }

if (!specs.length) {
  log('No specs provided. Invoke with args: { specs: ["spec/models/foo_spec.rb"], runs: 5 }')
} else {
  log(`Hunting ${specs.length} spec(s), ${runs} runs each.`)
  phase('Hunt')
  const results = (await parallel(specs.map((spec) => () =>
    agent(
      `Run the RSpec file \`${spec}\` exactly ${runs} times in this repo — each as a separate ` +
      `\`bundle exec rspec ${spec}\` invocation (do NOT use --repeat; separate processes catch ` +
      `order/state leakage). Count how many of the ${runs} runs passed vs failed. Classify: ` +
      `"stable" if all ${runs} passed, "failing" if all ${runs} failed, "flaky" if mixed. For ` +
      `flaky or failing, put the failing example description(s) and the error summary in notes. ` +
      `Return the structured result.`,
      { label: `hunt:${spec}`, phase: 'Hunt', schema: SCHEMA, effort: 'low' },
    ),
  ))).filter(Boolean)

  phase('Summarize')
  out = {
    flaky: results.filter((r) => r.classification === 'flaky'),
    failing: results.filter((r) => r.classification === 'failing'),
    stable: results.filter((r) => r.classification === 'stable'),
    all: results,
  }
  log(`${out.flaky.length} flaky, ${out.failing.length} failing, ${out.stable.length} stable.`)
}

return out
