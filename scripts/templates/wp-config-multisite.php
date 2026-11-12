<?php
/*
 * Added by studio-installer. WordPress Studio's own requests arrive as
 * localhost:<port>. The network only knows its custom domain, so map them to it.
 */
if ( defined( 'DOMAIN_CURRENT_SITE' ) && isset( $_SERVER['HTTP_HOST'] )
	&& preg_match( '/^(localhost|127\.0\.0\.1)(:\d+)?$/', $_SERVER['HTTP_HOST'] ) ) {
	$_SERVER['HTTP_HOST'] = DOMAIN_CURRENT_SITE;
}
