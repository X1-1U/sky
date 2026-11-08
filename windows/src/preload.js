const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('sky', {
  act: (name, ...args) => ipcRenderer.invoke('act', name, ...args),
  snapshot: () => ipcRenderer.invoke('snapshot'),
  onState: (cb) => ipcRenderer.on('state', (_e, s) => cb(s)),
});
