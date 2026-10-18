<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {

        $this->setPathInfoMode(false);
        $routeCollector->get('/search', '/search');
        $routeCollector->get('/{docPath:.+\.md}', '/parseDoc');
    }
}
