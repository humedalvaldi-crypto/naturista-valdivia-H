import { createApp } from './app';

// Punto de entrada del Worker. Solo exporta el handler por defecto:
// workerd trata cualquier otra exportación como un handler y fallaría al arrancar.
export default createApp();
