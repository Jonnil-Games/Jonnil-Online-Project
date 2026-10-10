/* Signed player IDs preserve noone.
Positions use signed world-pixel coordinates */
#macro TYPE_ID				buffer_s16
#macro TYPE_POSITION		buffer_s32

/* Versioned joins advertise gameplay protocol three so pets require compatible
peers. Client movement has its own protocol-one version field */
#macro GAMEPLAY_PROTOCOL_VERSION 3
#macro CLIENT_MOVEMENT_PROTOCOL_VERSION 1

#region /* Packet Type IDs */
/* Packet type bytes identify the body layout read by client/server dispatch.
These fixed numeric IDs must stay stable for existing peers and saved protocol
examples. The inline names below identify the responsibility of each packet */
#macro N_ID					0 /* Server assigns the client logical player slot */
#macro N_MESSAGE			1 /* Chat content and its sender metadata */
#macro N_NEW_PLAYER			2 /* One player joins the existing client roster */
#macro N_PLAYER_LIST		3 /* Initial connected-player roster */
#macro N_REMOVE_PLAYER		4 /* Remove a departed player from client state */

/* Movement */
#macro N_KEY_PRESS			5 /* Legacy movement action begins */
#macro N_KEY_RELEASE		6 /* Legacy movement action ends */
#macro N_PLAYER_POSITION	7 /* One player world-position update */
#macro N_SERVER_FULL		8 /* Join rejected because player capacity is reached */
#macro N_SERVER_STATUS		9 /* Server listing/status response */
#macro N_SERVER_STATUS_REQUEST	10 /* Request a listing/status response */
#macro N_JOIN_GAME			11 /* Legacy join request without gameplay version negotiation */
#macro N_LEAVE_GAME			12 /* Client leaves gameplay for the server list */
#macro N_PLAYER_POSITION_BATCH	13 /* Multiple player positions in one update */
#macro N_HEARTBEAT_PING		14 /* Server asks whether the client connection is responsive */
#macro N_HEARTBEAT_PONG		15 /* Client answers the server heartbeat */
#macro N_TYPING_STATE		16 /* Chat typing indicator changes */
#macro N_AFK_ACTIVITY		17 /* Client reports gameplay activity for AFK tracking */
#macro N_AFK_STATE			18 /* Server broadcasts the player AFK indicator */
#macro N_SERVER_KICK		19 /* Server removes the client with a reason */
#macro N_DRAW_COMMAND		20 /* Shared drawing operation */
#macro N_DRAW_HISTORY		21 /* Drawing-history synchronization */
#macro N_PLAYER_STATE_BATCH	22 /* Batch of player state including movement */
#macro N_DRAW_IMAGE			23 /* Chunked shared image upload or delivery */
#macro N_COLLISION_OBJECT_STATE	24 /* Shared collision-object state */
#macro N_PLAYER_CHARACTER	25 /* Character manifest and identity */
#macro N_PLAYER_CHARACTER_CHUNK	26 /* Character asset chunk */
#macro N_HOST_STATUS			27 /* Local host ownership/status indicator */
#macro N_SERVER_LIFECYCLE		28 /* Drawing-reset countdown or server lifecycle action */
#macro N_LATENCY_PROBE			29 /* Client round-trip probe sequence */
#macro N_LATENCY_REPLY			30 /* Server echoes a round-trip probe sequence */
#macro N_CLIENT_PLAYER_STATE	31 /* Client-authoritative movement state */
#macro N_CLIENT_PLAYER_STATE_ACK 32 /* Server acceptance/correction for movement state */
#macro N_LAYER_VOTE			33 /* Drawing-layer vote synchronization or ballot */
#macro N_ADMIN_AUTH			34 /* Remote administrator credential request */
#macro N_ADMIN_STATUS		35 /* Administrator status request or reply */
#macro N_ADMIN_COMMAND		36 /* Administrator server-setting or lifecycle command */
#macro N_ADMIN_RESULT		37 /* Administrator request outcome */
#macro N_SERVER_PLAYER_LIMIT 38 /* Server gameplay capacity update */
#macro N_JOIN_GAME_VERSIONED 39 /* Join request carrying gameplay compatibility version */
#macro N_ADMIN_LOGS          40 /* Administrator log-export request or transfer */
#macro N_WALL_SETTINGS       41 /* Wall-drawing policy update */
#macro N_WALL_EDIT           42 /* Client wall edit operation */
#macro N_WALL_SNAPSHOT       43 /* Shared wall-layout synchronization */
#macro N_WALL_PLAYER_CORRECTION 44 /* Player position correction following wall state */
#macro N_PLAYER_PET          45 /* Equipped cosmetic pet manifest or pet removal */


/* Layer-vote packets carry a subtype byte. STATE synchronizes an open vote,
CAST records a ballot, and RESULT announces the completed outcome */
#macro LAYER_VOTE_PACKET_STATE	0
#macro LAYER_VOTE_PACKET_CAST	1
#macro LAYER_VOTE_PACKET_RESULT	2


/* Layer-vote actions identify whether the proposed change archives, moves,
or restores a drawing layer. They share the action field in vote packets */
#macro LAYER_VOTE_ACTION_ARCHIVE	0
#macro LAYER_VOTE_ACTION_MOVE	1
#macro LAYER_VOTE_ACTION_RESTORE	2


/* Vote results distinguish approval, rejection and cancellation so peers can
apply an approved change or clear the vote without applying it */
#macro LAYER_VOTE_RESULT_APPROVED	0
#macro LAYER_VOTE_RESULT_REJECTED	1
#macro LAYER_VOTE_RESULT_CANCELLED	2


/* Admin messages use protocol one independently of gameplay compatibility.
The action field below selects authentication, status or a requested server change */
#macro ADMIN_PROTOCOL_VERSION	1

#macro ADMIN_ACTION_AUTH				0
#macro ADMIN_ACTION_STATUS			1
#macro ADMIN_ACTION_SET_RESET_ENABLED	2
#macro ADMIN_ACTION_SET_RESET_INTERVAL	3
#macro ADMIN_ACTION_RESET_NOW			4
#macro ADMIN_ACTION_FORCE_RESTART		5
#macro ADMIN_ACTION_SET_MAX_PLAYERS	6
#macro ADMIN_ACTION_SET_WALL_DRAWING	7


/* Admin reply result codes distinguish success, access denial, malformed input,
unavailable services, failed operations and cooldown rejection. Clients use them
to explain the request outcome without treating every failure as authentication */
#macro ADMIN_RESULT_OK			0
#macro ADMIN_RESULT_DENIED		1
#macro ADMIN_RESULT_INVALID		2
#macro ADMIN_RESULT_UNAVAILABLE	3
#macro ADMIN_RESULT_FAILED		4
#macro ADMIN_RESULT_RATE_LIMITED	5
#endregion /* Packet Type IDs END */

#region /* Chat Type IDs */
/* Chat entries distinguish named player messages, system announcements, errors
and slash-command speech. Receivers retain this type for display and export */
#macro CHAT_TYPE_PLAYER		0
#macro CHAT_TYPE_SYSTEM		1
#macro CHAT_TYPE_ERROR		2
#macro CHAT_TYPE_SAY		3
#endregion /* Chat Type IDs END */

#region /* Server Lifecycle Action IDs */
/* Lifecycle action IDs separate countdown/status updates, an immediate reset
notification and shutdown. The client uses them to update its server status */
#macro SERVER_LIFECYCLE_STATUS		0
#macro SERVER_LIFECYCLE_RESET_NOW	1
#macro SERVER_LIFECYCLE_SHUTDOWN		2
#endregion /* Server Lifecycle Action IDs END */
