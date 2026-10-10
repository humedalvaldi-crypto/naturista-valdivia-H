# deploy/

`api-url.txt` lo escribe el despliegue automático de la API
(`.github/workflows/deploy-api.yml`) con la dirección pública del Worker.
La publicación de la app web la usa si la variable `API_BASE_URL` del
repositorio está vacía. No contiene secretos.
