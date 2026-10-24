#!/usr/bin/env python3
"""Verify shared recording accounts with the same authenticated RPCs used by the app."""
import json, pathlib, urllib.request, urllib.error, uuid
root=pathlib.Path(__file__).resolve().parents[2]
codes=json.loads((root/'.recording/shared-credentials.json').read_text())
base='https://letuvtazmtjkvivattfy.supabase.co'
key='sb_publishable_2om3uiw5HBgQxNaBFEUZYA_g8Wfkxp6'
def call(path,body,token=None):
    req=urllib.request.Request(base+path,json.dumps(body).encode(),{'apikey':key,'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
    with urllib.request.urlopen(req) as r:return json.load(r)
auth={n:call('/auth/v1/token?grant_type=password',{'email':f'recording.{n}@courtly.app','password':codes[n]}) for n in codes}
def rpc(n,method,args=None): return call('/rest/v1/rpc/'+method,args or {},auth[n]['access_token'])
for n in auth:
    me=rpc(n,'get_me');feed=rpc(n,'get_play_feed');inbox=rpc(n,'get_inbox');requests=rpc(n,'get_friend_requests')
    assert len(inbox)>=2 and len(requests['incoming'])>=1
    assert 'Wellington' in json.dumps(me)
    print(n+': authenticated; populated feed, '+str(len(inbox))+' conversations, '+str(len(requests['incoming']))+' incoming friend requests.')
    (root/f'.recording/{n}-shared-inbox.json').write_text(json.dumps(inbox))
try:
    call('/auth/v1/token?grant_type=password',{'email':'recording.ana@courtly.app','password':'not-the-code'})
    raise AssertionError('Invalid password was accepted')
except urllib.error.HTTPError as e:
    assert e.code==400
print('Wrong code rejected. Both shared logins and authenticated app reads passed.')

ana_id=auth['ana']['user']['id'];luis_id=auth['luis']['user']['id']
inbox=rpc('ana','get_inbox')
dm=next(c['id'] for c in inbox if c['type']=='dm' and any(m['id']==luis_id for m in c['members']))
for n,body in [('ana','I will bring the tennis balls. See you by the courts!'),('luis','Perfect, see you there!')]:
    rpc(n,'send_message',{'p_chat':dm,'p_client_id':str(uuid.uuid4()),'p_body':body})
page=rpc('luis','get_chat_page',{'p_chat':dm,'p_limit':50})
assert 'I will bring the tennis balls.' in json.dumps(page)
assert 'Perfect, see you there!' in json.dumps(rpc('ana','get_chat_page',{'p_chat':dm,'p_limit':50}))
print('Bidirectional chat writes and reads passed on the hosted backend.')
