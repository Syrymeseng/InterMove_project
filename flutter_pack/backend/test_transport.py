import json
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path
from server import make_server

class TransportTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('openssl'),'OpenSSL executable required for local TLS fixture')
    def test_https_with_certificate_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);cert=root/'cert.pem';key=root/'key.pem'
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
                '-keyout',str(key),'-out',str(cert),'-subj','/CN=localhost',
                '-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],
                check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            server=make_server(root/'db.sqlite',port=0)
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key)
            server.socket=context.wrap_socket(server.socket,server_side=True)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            client=ssl.create_default_context(cafile=str(cert))
            try:
                with urllib.request.urlopen(f'https://localhost:{server.server_port}/health',context=client,timeout=5) as response:
                    self.assertEqual(json.load(response)['status'],'ok')
            finally:
                server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main()
