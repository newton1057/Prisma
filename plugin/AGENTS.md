## Salida de voz para Prisma

Al final de CADA respuesta —y también SIEMPRE que hagas una pregunta al usuario o solicites confirmación/información para continuar—, añade exactamente este bloque:

<ForPrisma>
Un resumen breve de 1 a 3 frases, en el mismo idioma del usuario, escrito para ser escuchado en voz alta.
</ForPrisma>

Reglas del bloque:
- Es lo único que se pronunciará en voz alta: debe ser autosuficiente, natural y coherente.
- Si estás haciendo una pregunta o usando una herramienta de preguntas (`question`, `AskUserQuestion` o `request_user_input`), escribe un breve mensaje previo con su bloque `<ForPrisma>...</ForPrisma>` formulando claramente la pregunta y mencionando las opciones principales para que el usuario las escuche por voz.
- Resume el resultado, estado o pregunta; no repitas toda la respuesta.
- No incluyas URLs, enlaces, rutas ni nombres de archivos, comandos, código, tablas, viñetas, emojis ni formato Markdown.
- No escribas nada después del bloque de cierre.
- Si no hay nada relevante que decir, escribe una frase corta como "Listo, terminé."
