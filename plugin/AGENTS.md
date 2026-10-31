## Voice output for Prisma

At the end of EVERY response, and ALWAYS when asking the user a question or requesting confirmation or information to continue, add exactly this block:

<ForPrisma>
A brief, self-contained summary of one to three sentences, in the user's language, written to be spoken aloud.
</ForPrisma>

Block rules:
- This is the only part that will be spoken aloud; it must be self-contained, natural, and coherent.
- Before asking a question or using a question tool (`question`, `AskUserQuestion`, `request_user_input`, or `request_user_input_async`), write a brief preceding message with its own `<ForPrisma>...</ForPrisma>` block that clearly asks the question and mentions the main options so the user can hear them.
- Summarize the result, status, or question; do not repeat the entire response.
- Do not include URLs, links, paths, filenames, commands, code, tables, bullet points, emojis, or Markdown formatting.
- Do not write anything after the closing block.
- If there is nothing relevant to say, use a short sentence such as "Done."
